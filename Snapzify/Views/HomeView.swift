import SwiftUI
import PhotosUI
import AVFoundation
import os.log

// Movie transferable for video handling
struct Movie: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "video_\(UUID().uuidString).mov")
            if FileManager.default.fileExists(atPath: copy.path()) {
                try FileManager.default.removeItem(at: copy)
            }
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

struct HomeView: View {
    @StateObject var vm: HomeViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var appState: AppState
    @State private var lastRefreshTime = Date()
    @State private var isVisible = true
    private let logger = Logger(subsystem: "com.snapzify.app", category: "HomeView")
    
    var body: some View {
        RootBackground {
            if vm.isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: T.S.lg) {
                        
                        // Show all active processing tasks
                        ForEach(vm.activeProcessingTasks) { task in
                            processingTaskView(task: task)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                        }
                        
                        // Legacy processing indicator (fallback)
                        if vm.isProcessing && vm.activeProcessingTasks.isEmpty {
                            processingIndicator
                        }
                        
                        if let errorMessage = vm.errorMessage {
                            errorBanner(message: errorMessage)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                                .onAppear {
                                    // Auto-dismiss after 3 seconds
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            vm.errorMessage = nil
                                        }
                                    }
                                }
                        }
                        
                        quickActions
                        
                        reverseSnapzifySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    // Manual refresh - check for latest photo immediately
                    await vm.checkForLatestScreenshot()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text("Snapzify")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(T.C.ink)
                    
                    Image("logo_header")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 64)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(T.C.ink)
                }
            }
        }
        .preferredColorScheme(.dark)
        .photosPicker(
            isPresented: $vm.showPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotos) { newValues in
            guard !newValues.isEmpty else { return }
            
            Task {
                // Queue all selected photos for batch processing
                var queuedImages: [UIImage] = []
                var queuedVideos: [URL] = []
                
                // Load all media items
                for (index, item) in newValues.enumerated() {
                    print("Loading item \(index + 1) of \(newValues.count)")
                    
                    // Check if it's a video
                    if let movie = try? await item.loadTransferable(type: Movie.self) {
                        print("Video \(index + 1) loaded successfully")
                        queuedVideos.append(movie.url)
                    }
                    // Otherwise try as image
                    else if let data = try? await item.loadTransferable(type: Data.self),
                            let image = UIImage(data: data) {
                        print("Image \(index + 1) loaded successfully")
                        queuedImages.append(image)
                    } else {
                        print("Failed to load media data for item \(index + 1)")
                    }
                }
                
                // If we have any media to process
                if !queuedImages.isEmpty || !queuedVideos.isEmpty {
                    // Set up queue processing state
                    await MainActor.run {
                        appState.totalQueueItems = queuedImages.count + queuedVideos.count
                        appState.currentQueueItemIndex = 1
                        appState.queueProcessingProgress = 0
                        appState.isProcessingQueue = true
                    }
                    
                    // Process all items and collect documents
                    var processedDocuments: [Document] = []
                    
                    // Process images
                    for (index, image) in queuedImages.enumerated() {
                        logger.info("Processing image \(index + 1) of \(queuedImages.count)")
                        
                        await MainActor.run {
                            appState.currentQueueItemIndex = index + 1
                            appState.queueProcessingProgress = 0
                        }
                        
                        do {
                            let document = try await vm.processImageForQueue(image)
                            processedDocuments.append(document)
                        } catch {
                            logger.error("Failed to process image \(index + 1): \(error)")
                        }
                    }
                    
                    // Process videos
                    for (index, videoURL) in queuedVideos.enumerated() {
                        logger.info("Processing video \(index + 1) of \(queuedVideos.count)")
                        
                        await MainActor.run {
                            appState.currentQueueItemIndex = queuedImages.count + index + 1
                            appState.queueProcessingProgress = 0
                        }
                        
                        do {
                            let document = try await vm.processVideoForQueue(videoURL)
                            processedDocuments.append(document)
                            logger.info("Successfully processed video \(index + 1)")
                        } catch {
                            logger.error("Failed to process video \(index + 1): \(error)")
                        }
                    }
                    
                    // Show queue view with all processed documents
                    await MainActor.run {
                        if !processedDocuments.isEmpty {
                            logger.info("Multi-select complete - Setting \(processedDocuments.count) documents in queue")
                            appState.queueDocuments = processedDocuments
                            appState.currentQueueIndex = 0
                            appState.currentQueueDocument = processedDocuments[0]
                            appState.isProcessingQueue = false
                            
                            // Trigger navigation to queue view
                            NotificationCenter.default.post(name: .openQueueDocument, object: processedDocuments[0])
                        } else {
                            logger.info("No documents processed from multi-select")
                            appState.isProcessingQueue = false
                        }
                    }
                }
                
                // Clear selection
                selectedPhotos = []
            }
        }
        .onAppear {
            isVisible = true
            
            // Check for latest screenshot once on appear
            Task {
                await vm.checkForLatestScreenshot()
            }
            
            // Shared images and action extension images are checked at app level
        }
        .onDisappear {
            isVisible = false
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // Shared images and action extension images are checked at app level when app becomes active
                
                // Refresh when scene becomes active
                let now = Date()
                if now.timeIntervalSince(lastRefreshTime) > 0.5 {
                    Task {
                        await vm.checkForLatestScreenshot()
                    }
                    lastRefreshTime = now
                }
            }
        }
    }
    
    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: T.S.md) {
            Button {
                vm.pickScreenshot()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .foregroundStyle(T.C.ink)
            }
            .buttonStyle(SecondaryButtonStyle())
            
            Button {
                vm.processLatest()
            } label: {
                Label("Most Recent", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(T.C.ink)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(vm.isProcessing || vm.latestInfo == nil)
        }
    }
    
    @ViewBuilder
    private var reverseSnapzifySection: some View {
        ReverseSnapzifyView(
            text: $vm.reverseSnapzifyText,
            translationResult: $vm.translationResult,
            isTranslating: vm.isTranslating,
            onTranslate: {
                Task {
                    await vm.performReverseSnapzify()
                }
            }
        )
    }
    
    @ViewBuilder
    private var loadingView: some View {
        ScrollView {
            VStack(spacing: T.S.lg) {
                // Quick actions placeholder
                HStack(spacing: T.S.md) {
                    ShimmerView()
                        .frame(height: 44)
                        .cornerRadius(8)
                    
                    ShimmerView()
                        .frame(height: 44)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 24)
        }
        .scrollIndicators(.hidden)
    }
    
    @ViewBuilder
    private var processingIndicator: some View {
        HStack(spacing: T.S.md) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Snapzifying...")
                .foregroundStyle(T.C.ink2)
                .font(.subheadline)
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private func processingTaskView(task: HomeViewModel.ProcessingTask) -> some View {
        HStack(spacing: T.S.md) {
            // Thumbnail
            if let thumbnail = task.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(T.C.ink.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
            }
            
            Spacer()
            
            // Just show the percentage
            Text(task.progress)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(T.C.ink)
                .frame(minWidth: 50, alignment: .trailing)
        }
        .padding()
        .card()
    }
    
    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: T.S.md) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.headline)
            
            Text(message)
                .foregroundStyle(.red)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button("Dismiss") {
                withAnimation(.easeInOut(duration: 0.3)) {
                    vm.errorMessage = nil
                }
            }
            .foregroundStyle(.red)
            .font(.caption.weight(.medium))
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
    
}

