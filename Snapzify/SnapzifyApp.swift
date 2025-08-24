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
            
            if url.host == "open" {
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
        // Shared content is now handled by HomeView's checkForSharedImages
        logger.debug("Shared content checking moved to HomeView")
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
    }
    
}

class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "AppState")
    @Published var shouldRefreshDocuments = false
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