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
    @State private var photoCheckTimer: Timer?
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
                        
                        savedSection
                        
                        if !vm.documents.isEmpty {
                            recentDocuments
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    // Manual refresh - check for latest photo immediately
                    await vm.checkForLatestScreenshot()
                    await vm.refreshSavedDocuments()
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
                // Create all tasks first
                var taskIds: [(PhotosPickerItem, UUID)] = []
                
                for (index, item) in newValues.enumerated() {
                    let taskId = UUID()
                    taskIds.append((item, taskId))
                    
                    await MainActor.run {
                        let task = HomeViewModel.ProcessingTask(
                            id: taskId,
                            name: "Media \(index + 1)/\(newValues.count)",
                            progress: "Preparing",
                            progressValue: 0.0,
                            totalFrames: 0,
                            processedFrames: 0,
                            type: .video,
                            thumbnail: nil
                        )
                        vm.activeProcessingTasks.append(task)
                        vm.isProcessing = true
                    }
                }
                
                // Process all items concurrently
                await withTaskGroup(of: Void.self) { group in
                    for (index, (item, taskId)) in taskIds.enumerated() {
                        group.addTask {
                            print("Processing item \(index + 1) of \(newValues.count)")
                            
                            // Check if it's a video
                            if let movie = try? await item.loadTransferable(type: Movie.self) {
                                print("Video \(index + 1) loaded successfully, processing...")
                                // Always check isVisible at completion time inside processPickedVideoWithTask
                                await self.vm.processPickedVideoWithTask(movie.url, taskId: taskId, checkVisibility: { self.isVisible })
                            }
                            // Otherwise try as image
                            else if let data = try? await item.loadTransferable(type: Data.self),
                                    let image = UIImage(data: data) {
                                print("Image \(index + 1) loaded successfully, snapzifying...")
                                // Always check isVisible at completion time inside processPickedImageWithTask
                                await self.vm.processPickedImageWithTask(image, taskId: taskId, checkVisibility: { self.isVisible })
                            } else {
                                print("Failed to load media data for item \(index + 1)")
                                await MainActor.run {
                                    self.vm.activeProcessingTasks.removeAll { $0.id == taskId }
                                    if self.vm.activeProcessingTasks.isEmpty {
                                        self.vm.isProcessing = false
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Clear selection after all tasks are started
                selectedPhotos = []
            }
        }
        .onAppear {
            isVisible = true
            
            // Load documents only once
            Task {
                await vm.loadDocuments()
            }
            // Start polling for new photos every 2 seconds
            startPhotoPolling()
            
            // Shared images are checked at app level
            
            // Check for images from ActionExtension
            checkForActionExtensionImage()
            
            // Only refresh saved documents if not just launching
            if vm.hasLoadedDocuments {
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    await vm.refreshSavedDocuments()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentSavedStatusChanged)) { notification in
            // Update saved documents immediately when pin status changes
            if let document = notification.object as? Document {
                vm.updateDocumentSavedStatus(document)
            }
        }
        .onDisappear {
            isVisible = false
            // Stop polling when view disappears
            stopPhotoPolling()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // Shared images are checked at app level when app becomes active
                
                // Check for ActionExtension images
                checkForActionExtensionImage()
                
                // Resume polling when app becomes active
                startPhotoPolling()
                
                // Refresh when scene becomes active
                let now = Date()
                if now.timeIntervalSince(lastRefreshTime) > 0.5 {
                    Task {
                        await vm.refreshSavedDocuments()
                        await vm.checkForLatestScreenshot()
                    }
                    lastRefreshTime = now
                }
            } else if phase == .background {
                // Stop polling when app goes to background
                stopPhotoPolling()
            }
        }
        .onChange(of: appState.shouldProcessActionImage) { shouldProcess in
            if shouldProcess {
                checkForActionExtensionImage()
            }
        }
    }
    
    
    @ViewBuilder
    private var savedSection: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            HStack {
                Text("Saved")
                    .font(.title3)
                    .foregroundStyle(T.C.ink)
                
                Spacer()
            }
            .padding(.horizontal, T.S.xs)
            
            let hasAnyContent = !vm.savedDocuments.isEmpty
            
            if !hasAnyContent {
                HStack {
                    Text("No saved content yet")
                        .foregroundStyle(T.C.ink2)
                        .font(.subheadline)
                    Spacer()
                }
                .padding()
                .card()
            } else {
                VStack(spacing: 0) {
                    // Images first
                    ForEach(vm.savedDocuments) { doc in
                        documentRow(doc, showPinIcon: false)
                        
                        let isLast = doc.id == vm.savedDocuments.last?.id
                        if !isLast {
                            Divider()
                                .background(T.C.divider.opacity(0.6))
                                .padding(.leading, 78)
                        }
                    }
                }
                .card()
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
    private var recentDocuments: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            HStack {
                Text("Recent")
                    .font(.title3)
                    .foregroundStyle(T.C.ink)
                
                if vm.isProcessingSharedImage {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Snapzifying shared image...")
                            .font(.caption)
                            .foregroundStyle(T.C.ink2)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, T.S.xs)
            
            VStack(spacing: 0) {
                ForEach(Array(vm.documents.prefix(10).enumerated()), id: \.element.id) { index, doc in
                    documentRow(doc, showPinIcon: false)
                    
                    if index < min(9, vm.documents.count - 1) {
                        Divider()
                            .background(T.C.divider.opacity(0.6))
                            .padding(.leading, 78)
                    }
                }
            }
            .card()
        }
    }
    
    @ViewBuilder
    private func documentRow(_ doc: DocumentMetadata, showPinIcon: Bool = true) -> some View {
        HStack(spacing: T.S.md) {
            Group {
                if let thumbnailData = doc.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(T.C.outline.opacity(0.3), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "doc.text")
                                .foregroundStyle(T.C.ink2)
                                .font(.title2)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(documentTitle(for: doc))
                        .foregroundStyle(T.C.ink)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    if doc.isSaved && showPinIcon {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(T.C.accent)
                            .font(.caption2)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(T.C.ink2)
                .font(.caption)
        }
        .padding(.horizontal, T.S.md)
        .padding(.vertical, T.S.md)
        .contentShape(Rectangle())
        .onTapGesture {
            vm.open(doc)
        }
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
                
                // Saved section placeholder
                VStack(alignment: .leading, spacing: T.S.sm) {
                    HStack {
                        ShimmerView()
                            .frame(width: 60, height: 20)
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(.horizontal, T.S.xs)
                    
                    ShimmerView()
                        .frame(height: 100)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                // Recent section placeholder
                VStack(alignment: .leading, spacing: T.S.sm) {
                    HStack {
                        ShimmerView()
                            .frame(width: 60, height: 20)
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(.horizontal, T.S.xs)
                    
                    VStack(spacing: 0) {
                        ForEach(0..<3) { index in
                            HStack(spacing: T.S.md) {
                                ShimmerView()
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    ShimmerView()
                                        .frame(width: 150, height: 16)
                                        .cornerRadius(3)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, T.S.md)
                            .padding(.vertical, T.S.md)
                            
                            if index < 2 {
                                Divider()
                                    .background(T.C.divider.opacity(0.6))
                                    .padding(.leading, 78)
                            }
                        }
                    }
                    .card()
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
    
    private func documentTitle(for doc: DocumentMetadata) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Screenshot • \(formatter.string(from: doc.createdAt))"
    }
    
    private func startPhotoPolling() {
        // Stop any existing timer first
        stopPhotoPolling()
        
        // Check immediately
        Task {
            await vm.checkForLatestScreenshot()
        }
        
        // Check for shared images more frequently (every 0.5 seconds for first 5 seconds, then every 2 seconds)
        var checkCount = 0
        photoCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            checkCount += 1
            
            // Shared images are now checked at app level
            
            // After 10 checks (5 seconds), slow down to every 2 seconds
            if checkCount >= 10 {
                timer.invalidate()
                self.photoCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                    Task {
                        await self.vm.checkForLatestScreenshot()
                    }
                }
            } else {
                Task {
                    await self.vm.checkForLatestScreenshot()
                }
            }
        }
    }
    
    private func stopPhotoPolling() {
        photoCheckTimer?.invalidate()
        photoCheckTimer = nil
    }
    
    private func checkForSharedImages() {
        // Shared image checking is now handled at app level in SnapzifyApp
        // This ensures it works regardless of which view is currently active
        logger.debug("Shared content checking moved to app level")
    }
    
    private func checkForActionExtensionImage() {
        // Check if there's a pending image from ActionExtension
        guard let fileName = appState.pendingActionImage else { return }
        
        guard let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") else { return }
        
        let tempDirectory = sharedContainerURL.appendingPathComponent("ActionTemp")
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        
        if let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            // Clear the pending image
            appState.pendingActionImage = nil
            appState.shouldProcessActionImage = false
            
            // Process and open the image
            Task {
                await vm.processActionExtensionImage(image)
            }
            
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

