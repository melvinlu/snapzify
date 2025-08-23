import SwiftUI

@main
struct SnapzifyApp: App {
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
        print("App: Received URL: \(url.absoluteString)")
        
        if url.scheme == "snapzify" {
            print("App: Handling snapzify URL scheme")
            
            if url.host == "document" && url.pathComponents.contains("new") {
                print("App: Opening new document from share extension")
                // Handle new document from share extension
                appState.shouldOpenNewDocument = true
                appState.processSharedImage()
            } else if url.host == "open" {
                print("App: Refreshing documents")
                appState.shouldRefreshDocuments = true
            }
        } else {
            print("App: Unknown URL scheme: \(url.scheme ?? "nil")")
        }
    }
    
    private func handleShareComplete(_ activity: NSUserActivity) {
        if let action = activity.userInfo?["action"] as? String, action == "refresh-documents" {
            appState.shouldRefreshDocuments = true
        }
    }
    
    private func checkForSharedContent() {
        print("Main App: Checking for shared content")
        
        // Check if there's a pending shared image
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") else { 
            print("Main App: Failed to access UserDefaults for group.com.snapzify.app")
            return 
        }
        
        // Check if we should open a document
        if sharedDefaults.bool(forKey: "shouldOpenDocument") {
            print("Main App: Found shouldOpenDocument flag")
            
            // Check timestamp to ensure it's recent (within last 60 seconds)
            let timestamp = sharedDefaults.double(forKey: "sharedImageTimestamp")
            let timeDiff = Date().timeIntervalSince1970 - timestamp
            
            if timeDiff < 60 {
                print("Main App: Processing shared image (timestamp: \(timestamp), diff: \(timeDiff)s)")
                
                sharedDefaults.set(false, forKey: "shouldOpenDocument")
                sharedDefaults.synchronize()
                
                // Process the shared image
                appState.shouldOpenNewDocument = true
                appState.processSharedImage()
            } else {
                print("Main App: Shared content is too old (diff: \(timeDiff)s), ignoring")
                sharedDefaults.set(false, forKey: "shouldOpenDocument")
                sharedDefaults.synchronize()
            }
        } else {
            print("Main App: No shouldOpenDocument flag found")
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var selectedDocument: Document?
    
    private let store = DocumentStoreImpl()
    private let configService = ConfigServiceImpl()
    
    var body: some View {
        NavigationStack {
            HomeView(vm: HomeViewModel(
                store: store,
                ocrService: OCRServiceImpl(),
                scriptConversionService: ScriptConversionServiceImpl(),
                segmentationService: SentenceSegmentationServiceImpl(),
                pinyinService: PinyinServiceImpl(),
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
                        let document = await createDocumentFromImage(sharedImage)
                        selectedDocument = document
                        appState.shouldOpenNewDocument = false
                        appState.sharedImage = nil
                    }
                }
            }
        }
    }
    
    private func createDocumentFromImage(_ image: UIImage) async -> Document {
        // Process the image and create a new document
        let ocrService = OCRServiceImpl()
        let scriptConversionService = ScriptConversionServiceImpl()
        let segmentationService = SentenceSegmentationServiceImpl()
        let pinyinService = PinyinServiceImpl()
        
        do {
            // Perform OCR on the image
            let ocrLines = try await ocrService.recognizeText(in: image)
            
            // Segment into sentences
            let sentencesWithBbox = await segmentationService.segmentIntoSentences(from: ocrLines)
            
            var processedSentences: [Sentence] = []
            for (sentenceText, bbox) in sentencesWithBbox {
                // Convert to simplified for consistency
                let simplifiedText = scriptConversionService.toSimplified(sentenceText)
                
                // Get pinyin
                let pinyin = await pinyinService.getPinyin(for: simplifiedText, script: .simplified)
                
                // Create sentence
                let sentence = Sentence(
                    text: simplifiedText,
                    rangeInImage: bbox,
                    pinyin: pinyin,
                    english: nil,
                    status: .ocrOnly,
                    isSaved: false
                )
                processedSentences.append(sentence)
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
            // Return empty document on error
            let imageData = image.jpegData(compressionQuality: 0.9)
            return Document(
                source: .shareExtension,
                script: .simplified,
                sentences: [],
                imageData: imageData,
                isSaved: false
            )
        }
    }
}

class AppState: ObservableObject {
    @Published var shouldRefreshDocuments = false
    @Published var shouldOpenNewDocument = false
    @Published var sharedImage: UIImage?
    
    func processSharedImage() {
        print("AppState: Processing shared image")
        
        // Get shared image from shared container
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") else {
            print("AppState: Failed to access UserDefaults")
            return
        }
        
        guard let fileName = sharedDefaults.string(forKey: "pendingSharedImage") else {
            print("AppState: No pending image filename found")
            return
        }
        
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") else {
            print("AppState: Failed to get shared container URL")
            return
        }
        
        print("AppState: Found pending image: \(fileName)")
        
        let imagesDirectory = sharedContainerURL.appendingPathComponent("SharedImages")
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        print("AppState: Looking for image at: \(fileURL.path)")
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("AppState: Image file exists")
            
            if let imageData = try? Data(contentsOf: fileURL),
               let image = UIImage(data: imageData) {
                print("AppState: Successfully loaded image, size: \(image.size)")
                self.sharedImage = image
                
                // Clean up
                sharedDefaults.removeObject(forKey: "pendingSharedImage")
                try? FileManager.default.removeItem(at: fileURL)
                print("AppState: Cleaned up shared image file")
            } else {
                print("AppState: Failed to load image data from file")
            }
        } else {
            print("AppState: Image file does not exist at path")
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
    
    func fetchSavedSentences() async throws -> [Sentence] {
        let all = try await fetchAll()
        let savedSentences = all.flatMap { document in
            document.sentences.filter { $0.isSaved }
        }
        return savedSentences
    }
}

enum StoreError: Error {
    case noDirectory
}