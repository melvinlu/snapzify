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
    private let serviceContainer = ServiceContainer.shared
    
    var body: some View {
        NavigationStack {
            HomeView(vm: serviceContainer.makeHomeViewModel(
                onOpenSettings: {
                    showSettings = true
                },
                onOpenDocument: { document in
                    selectedDocument = document
                }
            ))
            .navigationDestination(item: $selectedDocument) { document in
                DocumentView(vm: serviceContainer.makeDocumentViewModel(document: document))
            }
        }
        .tint(.white)
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: serviceContainer.makeSettingsViewModel())
        }
    }
    
}

class AppState: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "AppState")
    @Published var shouldRefreshDocuments = false
}