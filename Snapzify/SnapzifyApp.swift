import SwiftUI
import os.log

// Queue item structure (matches what ActionExtension writes)
struct QueueItem: Codable {
    let id: String
    let fileName: String
    let isVideo: Bool
    let queuedAt: Date
    let source: String
}

extension Notification.Name {
    static let openQueueDocument = Notification.Name("openQueueDocument")
}

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
                    logger.info("App became active - checking for shared content and queued media")
                    checkForSharedContent()
                    checkForQueuedMedia()
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
            } else if url.host == "process-image" {
                // Handle image from ActionExtension
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems,
                   let fileName = queryItems.first(where: { $0.name == "file" })?.value {
                    logger.info("Processing image from ActionExtension: \(fileName)")
                    appState.pendingActionImage = fileName
                    appState.shouldProcessActionImage = true
                }
            } else if url.host == "process-video" {
                // Handle video from ActionExtension
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems,
                   let fileName = queryItems.first(where: { $0.name == "file" })?.value {
                    logger.info("Processing video from ActionExtension: \(fileName)")
                    appState.pendingActionVideo = fileName
                    appState.shouldProcessActionVideo = true
                }
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
    
    private func checkForQueuedMedia() {
        logger.info("Checking for queued media...")
        
        // Check for queued media items - try app group first, then fallback to app container
        var containerURL: URL
        
        if let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) {
            containerURL = sharedContainerURL
            logger.info("Using shared container for queue")
        } else {
            // Fallback to app's Documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            containerURL = documentsPath.deletingLastPathComponent()
            logger.info("App group unavailable, using app container for queue")
        }
        
        let queueFileURL = containerURL.appendingPathComponent("mediaQueue.json")
        logger.info("Queue file path: \(queueFileURL.path)")
        
        // Load queue metadata
        guard let data = try? Data(contentsOf: queueFileURL) else {
            logger.info("No queue file found or unable to read")
            return
        }
        
        guard let queueItems = try? JSONDecoder().decode([QueueItem].self, from: data),
              !queueItems.isEmpty else {
            logger.info("Queue is empty or failed to decode")
            return
        }
        
        logger.info("Found \(queueItems.count) queued items")
        
        // Set total queue items for progress display
        appState.totalQueueItems = queueItems.count
        appState.currentQueueItemIndex = 1  // Start at 1 for display
        appState.queueProcessingProgress = 0
        appState.isProcessingQueue = true  // Show processing screen
        
        // Process ALL items in queue
        Task {
            await processAllQueuedItems(queueItems, containerURL: containerURL, queueFileURL: queueFileURL)
        }
    }
    
    private func processAllQueuedItems(_ queueItems: [QueueItem], containerURL: URL, queueFileURL: URL) async {
        let sortedItems = queueItems.sorted { $0.queuedAt < $1.queuedAt }
        var processedDocuments: [Document] = []
        
        for (index, item) in sortedItems.enumerated() {
            logger.info("Processing queue item \(index + 1) of \(sortedItems.count)")
            
            // Update progress - show which item we're processing
            await MainActor.run {
                appState.currentQueueItemIndex = index + 1
                appState.queueProcessingProgress = 0  // Start at 0% for each item
            }
            
            let queueDirectory = containerURL.appendingPathComponent("QueuedMedia")
            let fileURL = queueDirectory.appendingPathComponent(item.fileName)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let mediaData = try? Data(contentsOf: fileURL) {
                    if item.isVideo {
                        // TODO: Process video
                        logger.info("Video processing not yet implemented for batch queue")
                    } else {
                        // Process as image
                        if let image = UIImage(data: mediaData) {
                            logger.info("Processing image \(index + 1) of \(sortedItems.count)")
                            
                            // Process the image and get the document
                            if let document = await processQueuedImage(image, progressIndex: index, totalItems: sortedItems.count) {
                                processedDocuments.append(document)
                            }
                        }
                    }
                    
                    // Clean up the file
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
        
        // Clear the queue file
        try? FileManager.default.removeItem(at: queueFileURL)
        
        // All items processed, now show the first document
        await MainActor.run {
            if !processedDocuments.isEmpty {
                logger.info("📱 QUEUE COMPLETE - Setting \(processedDocuments.count) documents in queue")
                appState.queueDocuments = processedDocuments
                appState.currentQueueIndex = 0
                appState.currentQueueDocument = processedDocuments[0]
                appState.isProcessingQueue = false
                
                logger.info("📱 Queue documents set: \(appState.queueDocuments.map { $0.id })")
                
                // Navigate to the first document
                if let contentView = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController {
                    // This will trigger navigation through the ContentView's state
                    NotificationCenter.default.post(name: .openQueueDocument, object: processedDocuments[0])
                }
            } else {
                logger.info("📱 No documents processed from queue")
                appState.isProcessingQueue = false
            }
        }
    }
    
    private func processQueuedImage(_ image: UIImage, progressIndex: Int, totalItems: Int) async -> Document? {
        // Create a temporary HomeViewModel instance to process the image
        let serviceContainer = ServiceContainer.shared
        let homeViewModel = serviceContainer.makeHomeViewModel(
            onOpenSettings: { },
            onOpenDocument: { _ in }
        )
        
        // Set up progress callback based on Chinese text processing
        homeViewModel.onProcessingProgress = { progress in
            Task { @MainActor in
                // Progress is 0-1 based on Chinese lines processed
                appState.queueProcessingProgress = Int(progress * 100)
                logger.info("Queue item \(progressIndex + 1)/\(totalItems) - Chinese lines progress: \(appState.queueProcessingProgress)%")
            }
        }
        
        do {
            // Process the image and return the document
            let document = try await homeViewModel.processImageForQueue(image)
            return document
        } catch {
            logger.error("Failed to process queued image: \(error)")
            return nil
        }
    }
    
    private func checkForSharedContent() {
        // Check if there's a pending shared image from the share extension
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") else { return }
        
        // Check if we should process a shared image
        if let fileName = sharedDefaults.string(forKey: "pendingSharedImage") {
            logger.info("Found pending shared image: \(fileName)")
            
            // Load the shared image
            if let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") {
                let imagesDirectory = sharedContainerURL.appendingPathComponent("SharedImages")
                let fileURL = imagesDirectory.appendingPathComponent(fileName)
                
                if let imageData = try? Data(contentsOf: fileURL),
                   let image = UIImage(data: imageData) {
                    logger.info("Loaded shared image, setting for processing")
                    
                    // Clear the pending image flag
                    sharedDefaults.removeObject(forKey: "pendingSharedImage")
                    sharedDefaults.removeObject(forKey: "sharedImageTimestamp")
                    sharedDefaults.synchronize()
                    
                    // Store image for processing
                    appState.pendingSharedImage = image
                    appState.shouldProcessSharedImage = true
                    
                    // Clean up the file
                    try? FileManager.default.removeItem(at: fileURL)
                } else {
                    // If file doesn't exist, clear the pending flag
                    logger.warning("Shared image file not found, clearing flag")
                    sharedDefaults.removeObject(forKey: "pendingSharedImage")
                    sharedDefaults.removeObject(forKey: "sharedImageTimestamp")
                    sharedDefaults.synchronize()
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var selectedDocument: Document?
    @State private var navigationPath = NavigationPath()
    @State private var actionExtensionImage: IdentifiableImage?
    @State private var actionExtensionVideo: IdentifiableVideoURL?
    @State private var showQueueProcessing = false
    @State private var showingQueueView = false
    @StateObject private var homeVM: HomeViewModel
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "ContentView")
    private let serviceContainer = ServiceContainer.shared
    
    init() {
        let container = ServiceContainer.shared
        let homeViewModel = container.makeHomeViewModel(
            onOpenSettings: { },
            onOpenDocument: { _ in }
        )
        _homeVM = StateObject(wrappedValue: homeViewModel)
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            HomeView(vm: homeVM)
                .onAppear {
                    // Set up the callbacks after view appears
                    homeVM.onOpenSettings = {
                        showSettings = true
                    }
                    homeVM.onOpenDocument = { document in
                        selectedDocument = document
                    }
                    // Set appState reference
                    homeVM.appState = appState
                }
                .onReceive(NotificationCenter.default.publisher(for: .openQueueDocument)) { notification in
                    if let document = notification.object as? Document {
                        // Check if we have multiple queue documents
                        if appState.queueDocuments.count > 1 {
                            // Show queue view for multiple documents
                            showingQueueView = true
                        } else {
                            // Show single document
                            selectedDocument = document
                        }
                    }
                }
                .navigationDestination(item: $selectedDocument) { document in
                    // Single document view (when not in queue mode)
                    if document.isVideo {
                        VideoDocumentView(vm: serviceContainer.makeDocumentViewModel(document: document))
                    } else {
                        DocumentView(vm: serviceContainer.makeDocumentViewModel(document: document))
                    }
                }
                .navigationDestination(for: Document.self) { document in
                    if document.isVideo {
                        VideoDocumentView(vm: serviceContainer.makeDocumentViewModel(document: document))
                    } else {
                        DocumentView(vm: serviceContainer.makeDocumentViewModel(document: document))
                    }
                }
                .fullScreenCover(item: $actionExtensionImage) { identifiableImage in
                    NavigationStack {
                        ActionExtensionLoadingView(image: identifiableImage.image, navigationPath: .constant(NavigationPath())) { document in
                            // Dismiss loading view and navigate to document
                            actionExtensionImage = nil
                            
                            // If a document is already selected, dismiss it first
                            if selectedDocument != nil {
                                selectedDocument = nil
                                // Small delay to allow dismissal before setting new document
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                                    selectedDocument = document
                                }
                            } else {
                                selectedDocument = document
                            }
                        }
                    }
                }
                .fullScreenCover(item: $actionExtensionVideo) { identifiableVideo in
                    NavigationStack {
                        ActionExtensionVideoLoadingView(videoURL: identifiableVideo.url, navigationPath: .constant(NavigationPath())) { document in
                            // Dismiss loading view and navigate to document
                            actionExtensionVideo = nil
                            
                            // If a document is already selected, dismiss it first
                            if selectedDocument != nil {
                                selectedDocument = nil
                                // Small delay to allow dismissal before setting new document
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                                    selectedDocument = document
                                }
                            } else {
                                selectedDocument = document
                            }
                        }
                    }
                }
        }
        .tint(.white)
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: serviceContainer.makeSettingsViewModel())
        }
        .fullScreenCover(isPresented: $appState.isProcessingQueue) {
            QueueProcessingView()
                .environmentObject(appState)
        }
        .fullScreenCover(isPresented: $showingQueueView) {
            if !appState.queueDocuments.isEmpty {
                QueueDocumentView(
                    documents: appState.queueDocuments,
                    initialIndex: appState.currentQueueIndex
                )
                .environmentObject(appState)
            }
        }
        .onAppear {
            // Set up callbacks after view is created
            homeVM.onOpenSettings = {
                showSettings = true
            }
            homeVM.onOpenDocument = { document in
                logger.info("Opening document: \(document.id)")
                // Dismiss current document first if showing one
                if selectedDocument != nil {
                    selectedDocument = nil
                    // Small delay to allow dismissal
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                        selectedDocument = document
                    }
                } else {
                    selectedDocument = document
                }
            }
            // Set appState reference
            homeVM.appState = appState
        }
        .onChange(of: appState.shouldProcessSharedImage) { shouldProcess in
            logger.info("onChange shouldProcessSharedImage triggered: \(shouldProcess)")
            if shouldProcess, let image = appState.pendingSharedImage {
                logger.info("Processing shared image from app state - isQueue: \(appState.shouldProcessQueue)")
                
                Task {
                    // Use processQueuedImage if this is from the queue, otherwise use processSharedImage
                    if appState.shouldProcessQueue {
                        logger.info("Processing as queued image")
                        await homeVM.processQueuedImage(image)
                        await MainActor.run {
                            appState.shouldProcessQueue = false
                        }
                    } else {
                        logger.info("Processing as shared image")
                        await homeVM.processSharedImage(image)
                    }
                    await MainActor.run {
                        appState.shouldProcessSharedImage = false
                        appState.pendingSharedImage = nil
                    }
                }
            } else {
                logger.info("Skipping processing - shouldProcess: \(shouldProcess), hasImage: \(appState.pendingSharedImage != nil)")
            }
        }
        .onChange(of: appState.shouldProcessActionImage) { shouldProcess in
            if shouldProcess, let fileName = appState.pendingActionImage {
                logger.info("Processing action extension image: \(fileName)")
                
                // Load image from shared container
                guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") else { return }
                
                let tempDirectory = sharedContainerURL.appendingPathComponent("ActionTemp")
                let fileURL = tempDirectory.appendingPathComponent(fileName)
                
                if let imageData = try? Data(contentsOf: fileURL),
                   let image = UIImage(data: imageData) {
                    // Show loading view
                    actionExtensionImage = IdentifiableImage(image: image)
                    
                    // Clear the pending state
                    appState.pendingActionImage = nil
                    appState.shouldProcessActionImage = false
                    
                    // Clean up the temp file
                    try? FileManager.default.removeItem(at: fileURL)
                    
                    // Clean up the temp directory if empty
                    if let contents = try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil),
                       contents.isEmpty {
                        try? FileManager.default.removeItem(at: tempDirectory)
                    }
                } else {
                    // Clear invalid pending image
                    appState.pendingActionImage = nil
                    appState.shouldProcessActionImage = false
                }
            }
        }
        .onChange(of: appState.shouldProcessActionVideo) { shouldProcess in
            if shouldProcess, let fileName = appState.pendingActionVideo {
                logger.info("Processing action extension video: \(fileName)")
                
                // Load video from shared container
                guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") else { return }
                
                let tempDirectory = sharedContainerURL.appendingPathComponent("ActionTemp")
                let fileURL = tempDirectory.appendingPathComponent(fileName)
                
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    // Show loading view for video processing
                    actionExtensionVideo = IdentifiableVideoURL(url: fileURL)
                    
                    // Clear the pending state
                    appState.pendingActionVideo = nil
                    appState.shouldProcessActionVideo = false
                    
                    // Note: Cleanup will be handled after processing in the loading view
                } else {
                    // Clear invalid pending video
                    appState.pendingActionVideo = nil
                    appState.shouldProcessActionVideo = false
                }
            }
        }
    }
    
}

class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "AppState")
    @Published var shouldRefreshDocuments = false
    @Published var shouldProcessActionImage = false
    @Published var pendingActionImage: String?
    @Published var shouldProcessActionVideo = false
    @Published var pendingActionVideo: String?
    @Published var shouldProcessSharedImage = false
    @Published var pendingSharedImage: UIImage?
    @Published var shouldProcessQueue = false
    @Published var currentQueueDocument: Document?
    @Published var queueDocuments: [Document] = []
    @Published var currentQueueIndex: Int = 0
    @Published var isProcessingQueue = false
    @Published var queueProcessingProgress: Int = 0
    @Published var currentQueueItemIndex: Int = 1
    @Published var totalQueueItems: Int = 0
}