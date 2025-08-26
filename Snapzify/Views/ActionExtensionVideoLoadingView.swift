import SwiftUI
import AVKit

struct ActionExtensionVideoLoadingView: View {
    let videoURL: URL
    @StateObject private var vm: ActionExtensionVideoLoadingViewModel
    @Binding var navigationPath: NavigationPath
    let onComplete: (Document) -> Void
    @Environment(\.dismiss) private var dismiss
    
    init(videoURL: URL, navigationPath: Binding<NavigationPath>, onComplete: @escaping (Document) -> Void) {
        self.videoURL = videoURL
        self._navigationPath = navigationPath
        self.onComplete = onComplete
        self._vm = StateObject(wrappedValue: ActionExtensionVideoLoadingViewModel(
            store: ServiceContainer.shared.documentStore,
            ocrService: ServiceContainer.shared.ocrService,
            scriptConversionService: ServiceContainer.shared.scriptConversionService
        ))
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Video thumbnail
                if let thumbnail = vm.videoThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 200, maxHeight: 200)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .overlay(
                            // Play icon overlay
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.8))
                        )
                } else {
                    // Loading placeholder
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.5)
                        )
                }
                
                // "Snapzifying!" with percentage
                HStack(spacing: 8) {
                    Text("Snapzifying Video!")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(vm.processingPercentage)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Cancel button at bottom
                Button {
                    vm.cancelProcessing()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
        .navigationBarHidden(true)
        .task {
            await vm.processVideo(videoURL) { document in
                // Call completion handler when processing is done
                onComplete(document)
            }
        }
        .onDisappear {
            vm.cancelProcessing()
        }
    }
}

@MainActor
class ActionExtensionVideoLoadingViewModel: ObservableObject {
    @Published var processingPercentage: String = "0%"
    @Published var isProcessing = false
    @Published var videoThumbnail: UIImage?
    @Published var totalFrames: Int = 0
    @Published var processedFrames: Int = 0
    
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    @AppStorage("selectedScript") private var selectedScript: String = ChineseScript.simplified.rawValue
    
    private var processingTask: Task<Void, Never>?
    private var homeVM: HomeViewModel?
    
    init(store: DocumentStore, ocrService: OCRService, scriptConversionService: ScriptConversionService) {
        self.store = store
        self.ocrService = ocrService
        self.scriptConversionService = scriptConversionService
    }
    
    func processVideo(_ url: URL, onComplete: @escaping (Document) -> Void) async {
        isProcessing = true
        processingPercentage = "0%"
        
        // Generate thumbnail from first frame
        if let thumbnail = generateThumbnail(from: url) {
            videoThumbnail = thumbnail
        }
        
        processingTask = Task { @MainActor in
            // Create a HomeViewModel instance for video processing
            let homeVM = ServiceContainer.shared.makeHomeViewModel(
                onOpenSettings: {},
                onOpenDocument: { _ in }
            )
            
            // Create a task ID for tracking
            let taskId = UUID()
            
            // Track progress updates from the processing
            let progressObserver = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if let task = homeVM.activeProcessingTasks.first(where: { $0.id == taskId }) {
                    Task { @MainActor in
                        self.processingPercentage = task.progress
                        self.totalFrames = task.totalFrames
                        self.processedFrames = task.processedFrames
                    }
                }
            }
            
            // Process the video
            await homeVM.processPickedVideoWithTask(url, taskId: taskId, checkVisibility: { false }) // Don't navigate from here
            
            // Stop progress observer
            progressObserver.invalidate()
            
            // Clean up the temp file from action extension
            if url.path.contains("ActionTemp") {
                try? FileManager.default.removeItem(at: url)
                
                // Clean up the temp directory if empty
                let tempDirectory = url.deletingLastPathComponent()
                if let contents = try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil),
                   contents.isEmpty {
                    try? FileManager.default.removeItem(at: tempDirectory)
                }
            }
            
            // Find the processed document (should be the most recent)
            if let documentMetadata = homeVM.documents.first,
               let document = try? await store.fetch(id: documentMetadata.id) {
                processingPercentage = "100%"
                isProcessing = false
                onComplete(document)
            } else {
                // Fallback: something went wrong
                processingPercentage = "Error"
                isProcessing = false
            }
        }
        
        await processingTask?.value
    }
    
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }
    
    private func generateThumbnail(from url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        
        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}