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
    @StateObject private var homeVM: HomeViewModel
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "ContentView")
    private let serviceContainer = ServiceContainer.shared
    
    init() {
        let container = ServiceContainer.shared
        _homeVM = StateObject(wrappedValue: container.makeHomeViewModel(
            onOpenSettings: { },
            onOpenDocument: { _ in }
        ))
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            HomeView(vm: homeVM)
                .navigationDestination(item: $selectedDocument) { document in
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
        }
        .onChange(of: appState.shouldProcessSharedImage) { shouldProcess in
            if shouldProcess, let image = appState.pendingSharedImage {
                logger.info("Processing shared image from app state")
                
                Task {
                    await homeVM.processSharedImage(image)
                    await MainActor.run {
                        appState.shouldProcessSharedImage = false
                        appState.pendingSharedImage = nil
                    }
                }
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
}