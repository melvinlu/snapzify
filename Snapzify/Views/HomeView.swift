import SwiftUI
import PhotosUI

struct HomeView: View {
    @StateObject var vm: HomeViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime = Date()
    @State private var photoCheckTimer: Timer?
    
    var body: some View {
        RootBackground {
            if vm.isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: T.S.lg) {
                        
                        if vm.isProcessing {
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
            selection: $selectedPhoto,
            matching: .images
        )
        .onChange(of: selectedPhoto) { newValue in
            Task {
                if let newValue {
                    print("Photo selected, loading data...")
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        print("Image loaded successfully, snapzifying...")
                        vm.processPickedImage(image)
                    } else {
                        print("Failed to load image data")
                    }
                    selectedPhoto = nil
                }
            }
        }
        .task {
            await vm.loadDocuments()
        }
        .onAppear {
            // Start polling for new photos every 2 seconds
            startPhotoPolling()
            
            // Check for shared images from share extension
            checkForSharedImages()
            
            // Refresh saved documents when view appears
            // Add a small delay to ensure navigation has completed
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                await vm.refreshSavedDocuments()
            }
        }
        .onDisappear {
            // Stop polling when view disappears
            stopPhotoPolling()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // Resume polling when app becomes active
                startPhotoPolling()
                
                // Check for shared images when app becomes active
                checkForSharedImages()
                
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
    private func documentRow(_ doc: Document, showPinIcon: Bool = true) -> some View {
        HStack(spacing: T.S.md) {
            Group {
                if let imageData = doc.imageData,
                   let uiImage = UIImage(data: imageData) {
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
    
    private func documentTitle(for doc: Document) -> String {
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
        
        // Then check every 2 seconds
        photoCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task {
                await vm.checkForLatestScreenshot()
            }
        }
    }
    
    private func stopPhotoPolling() {
        photoCheckTimer?.invalidate()
        photoCheckTimer = nil
    }
    
    private func checkForSharedImages() {
        // Check if there's a pending shared image from the share extension
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.snapzify.app") else { return }
        
        // Check if we should process a shared image
        if let fileName = sharedDefaults.string(forKey: "pendingSharedImage") {
            // Check timestamp to ensure it's recent (within last 60 seconds)
            let timestamp = sharedDefaults.double(forKey: "sharedImageTimestamp")
            let timeDiff = Date().timeIntervalSince1970 - timestamp
            
            if timeDiff < 60 {
                // Load and process the shared image
                if let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") {
                    let imagesDirectory = sharedContainerURL.appendingPathComponent("SharedImages")
                    let fileURL = imagesDirectory.appendingPathComponent(fileName)
                    
                    if let imageData = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: imageData) {
                        // Clear the pending image flag
                        sharedDefaults.removeObject(forKey: "pendingSharedImage")
                        sharedDefaults.removeObject(forKey: "sharedImageTimestamp")
                        sharedDefaults.synchronize()
                        
                        // Process the image in background without opening
                        Task {
                            await vm.processSharedImage(image)
                        }
                        
                        // Clean up the file
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            } else {
                // Clear old pending image
                sharedDefaults.removeObject(forKey: "pendingSharedImage")
                sharedDefaults.removeObject(forKey: "sharedImageTimestamp")
                sharedDefaults.synchronize()
            }
        }
    }
}

