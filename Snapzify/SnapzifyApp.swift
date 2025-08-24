import SwiftUI
import os.log

@main
struct SnapzifyApp: App {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "Main")
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity("com.snapzify.share-complete") { activity in
                    handleShareComplete(activity)
                }
                .onAppear {
                    checkForSharedContent()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    checkForSharedContent()
                }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        logger.info("Received URL: \(url.absoluteString)")
        
        if url.scheme == "snapzify" {
            logger.debug("Handling snapzify URL scheme")
            
            if url.host == "document" && url.pathComponents.contains("new") {
                logger.info("Opening new document from share extension")
                // Handle new document from share extension
                appState.shouldOpenNewDocument = true
                appState.processSharedImage()
            } else if url.host == "open" {
                logger.debug("Refreshing documents")
                appState.shouldRefreshDocuments = true
            }
        } else {
            logger.warning("Unknown URL scheme: \(url.scheme ?? "nil")")
        }
    }
    
    private func handleShareComplete(_ activity: NSUserActivity) {
        if let action = activity.userInfo?["action"] as? String, action == "refresh-documents" {
            appState.shouldRefreshDocuments = true
        }
    }
    
    private func checkForSharedContent() {
        logger.debug("Checking for shared content")
        
        // Check if there's a pending shared image
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") else { 
            logger.error("Failed to access UserDefaults for group.com.snapzify.app")
            return 
        }
        
        // Check if we should open a document
        if sharedDefaults.bool(forKey: "shouldOpenDocument") {
            logger.info("Found shouldOpenDocument flag")
            
            // Check timestamp to ensure it's recent (within last 60 seconds)
            let timestamp = sharedDefaults.double(forKey: "sharedImageTimestamp")
            let timeDiff = Date().timeIntervalSince1970 - timestamp
            
            if timeDiff < 60 {
                logger.info("Processing shared image (timestamp: \(timestamp), diff: \(timeDiff)s)")
                
                sharedDefaults.set(false, forKey: "shouldOpenDocument")
                sharedDefaults.synchronize()
                
                // Process the shared image
                appState.shouldOpenNewDocument = true
                appState.processSharedImage()
            } else {
                logger.warning("Shared content is too old (diff: \(timeDiff)s), ignoring")
                sharedDefaults.set(false, forKey: "shouldOpenDocument")
                sharedDefaults.synchronize()
            }
        } else {
            logger.info("No shouldOpenDocument flag found")
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var selectedDocument: Document?
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "ContentView")
    private let store = DocumentStoreImpl()
    private let configService = ConfigServiceImpl()
    
    var body: some View {
        NavigationStack {
            HomeView(vm: HomeViewModel(
                store: store,
                ocrService: OCRServiceImpl(),
                scriptConversionService: ScriptConversionServiceImpl(),
                segmentationService: SentenceSegmentationServiceImpl(),
                pinyinService: PinyinServiceOpenAI(configService: ConfigServiceImpl()),
                onOpenSettings: {
                    showSettings = true
                },
                onOpenDocument: { document in
                    selectedDocument = document
                }
            ))
            .navigationDestination(item: $selectedDocument) { document in
                DocumentView(vm: DocumentViewModel(
                    document: document,
                    translationService: TranslationServiceOpenAI(configService: configService),
                    ttsService: TTSServiceOpenAI(configService: configService),
                    store: store
                ))
            }
        }
        .tint(.white)
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: SettingsViewModel(
                configService: configService,
                translationService: TranslationServiceOpenAI(configService: configService),
                ttsService: TTSServiceOpenAI(configService: configService)
            ))
        }
        .onReceive(appState.$shouldOpenNewDocument) { shouldOpen in
            if shouldOpen {
                // Create and open new document with shared image
                if let sharedImage = appState.sharedImage {
                    Task {
                        if let document = await createDocumentFromImage(sharedImage) {
                            selectedDocument = document
                        } else {
                            // Show error message if no Chinese detected
                            logger.warning("Cannot create document: No Chinese content detected")
                            // Note: You may want to show an alert or error message here
                        }
                        appState.shouldOpenNewDocument = false
                        appState.sharedImage = nil
                    }
                }
            }
        }
    }
    
    private func containsChinese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for CJK Unified Ideographs ranges
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) ||
               (0x2A700...0x2B73F).contains(scalar.value) ||
               (0x2B740...0x2B81F).contains(scalar.value) ||
               (0x2B820...0x2CEAF).contains(scalar.value) ||
               (0x2CEB0...0x2EBEF).contains(scalar.value) ||
               (0x30000...0x3134F).contains(scalar.value) {
                return true
            }
        }
        return false
    }
    
    private func createDocumentFromImage(_ image: UIImage) async -> Document? {
        // Process the image and create a new document
        let ocrService = OCRServiceImpl()
        let scriptConversionService = ScriptConversionServiceImpl()
        let segmentationService = SentenceSegmentationServiceImpl()
        let pinyinService = PinyinServiceOpenAI(configService: ConfigServiceImpl())
        
        do {
            // Perform OCR on the image
            let ocrLines = try await ocrService.recognizeText(in: image)
            
            // Segment into sentences
            let sentencesWithBbox = await segmentationService.segmentIntoSentences(from: ocrLines)
            
            var processedSentences: [Sentence] = []
            var hasChineseContent = false
            
            for (sentenceText, bbox) in sentencesWithBbox {
                // Check if this sentence contains Chinese
                if containsChinese(sentenceText) {
                    hasChineseContent = true
                    
                    // Convert to simplified for consistency
                    let simplifiedText = scriptConversionService.toSimplified(sentenceText)
                    
                    // Get pinyin
                    let pinyin = await pinyinService.getPinyin(for: simplifiedText, script: ChineseScript.simplified)
                    
                    // Create sentence
                    let sentence = Sentence(
                        text: simplifiedText,
                        rangeInImage: bbox,
                        pinyin: pinyin,
                        english: nil,
                        status: .ocrOnly
                    )
                    processedSentences.append(sentence)
                }
            }
            
            // If no Chinese content found, return nil
            if !hasChineseContent {
                logger.info("No Chinese content detected in shared image")
                return nil
            }
            
            // Convert image to data
            let imageData = image.jpegData(compressionQuality: 0.9)
            
            let document = Document(
                source: .shareExtension,
                script: .simplified,
                sentences: processedSentences,
                imageData: imageData,
                isSaved: false
            )
            
            try? await store.save(document)
            return document
        } catch {
            logger.error("Error processing shared image: \(error)")
            return nil
        }
    }
}

class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "AppState")
    @Published var shouldRefreshDocuments = false
    @Published var shouldOpenNewDocument = false
    @Published var sharedImage: UIImage?
    
    func processSharedImage() {
        logger.info("Processing shared image")
        
        // Get shared image from shared container
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") else {
            logger.error("Failed to access UserDefaults")
            return
        }
        
        guard let fileName = sharedDefaults.string(forKey: "pendingSharedImage") else {
            logger.info("No pending image filename found")
            return
        }
        
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") else {
            logger.error("Failed to get shared container URL")
            return
        }
        
        logger.info("Found pending image: \(fileName)")
        
        let imagesDirectory = sharedContainerURL.appendingPathComponent("SharedImages")
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        logger.debug("Looking for image at: \(fileURL.path)")
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            logger.debug("Image file exists")
            
            if let imageData = try? Data(contentsOf: fileURL),
               let image = UIImage(data: imageData) {
                logger.info("Successfully loaded image")
                self.sharedImage = image
                
                // Clean up
                sharedDefaults.removeObject(forKey: "pendingSharedImage")
                try? FileManager.default.removeItem(at: fileURL)
                logger.info("Cleaned up shared image file")
            } else {
                logger.info("Failed to load image data from file")
            }
        } else {
            logger.debug("Image file does not exist at path")
        }
    }
}

class DocumentStoreImpl: DocumentStore {
    private let fileManager = FileManager.default
    private var documentsDirectory: URL? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) else { return nil }
        
        return containerURL.appendingPathComponent("Documents")
    }
    
    init() {
        createDirectoryIfNeeded()
    }
    
    private func createDirectoryIfNeeded() {
        guard let dir = documentsDirectory else { return }
        
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    func save(_ document: Document) async throws {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let fileURL = dir.appendingPathComponent("\(document.id.uuidString).json")
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL)
    }
    
    func fetchAll() async throws -> [Document] {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        
        var documents: [Document] = []
        
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let document = try? JSONDecoder().decode(Document.self, from: data) {
                documents.append(document)
            }
        }
        
        return documents.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetch(id: UUID) async throws -> Document? {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let fileURL = dir.appendingPathComponent("\(id.uuidString).json")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Document.self, from: data)
    }
    
    func delete(id: UUID) async throws {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let fileURL = dir.appendingPathComponent("\(id.uuidString).json")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    func fetchLatest() async throws -> Document? {
        let all = try await fetchAll()
        return all.first
    }
    
    func deleteAll() async throws {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        
        for file in files where file.pathExtension == "json" {
            try fileManager.removeItem(at: file)
        }
    }
    
    func update(_ document: Document) async throws {
        try await save(document)
    }
    
    func fetchSaved() async throws -> [Document] {
        let all = try await fetchAll()
        return all.filter { $0.isSaved }
    }
}

enum StoreError: Error {
    case noDirectory
}