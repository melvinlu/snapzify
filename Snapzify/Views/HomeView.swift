import SwiftUI
import PhotosUI

struct HomeView: View {
    @StateObject var vm: HomeViewModel
    @State private var selectedPhoto: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefreshTime = Date()
    
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
            // Refresh saved documents when view appears
            // Add a small delay to ensure navigation has completed
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                await vm.refreshSavedDocuments()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                // Refresh when scene becomes active
                let now = Date()
                if now.timeIntervalSince(lastRefreshTime) > 0.5 {
                    Task {
                        await vm.refreshSavedDocuments()
                    }
                    lastRefreshTime = now
                }
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
            
            let hasAnyContent = !vm.savedDocuments.isEmpty || !vm.savedSentences.isEmpty
            
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
                        
                        let isLast = doc.id == vm.savedDocuments.last?.id && vm.savedSentences.isEmpty
                        if !isLast {
                            Divider()
                                .background(T.C.divider.opacity(0.6))
                                .padding(.leading, 78)
                        }
                    }
                    
                    // Sentences after images
                    ForEach(vm.savedSentences, id: \.id) { sentence in
                        savedSentenceRow(sentence)
                        
                        if sentence.id != vm.savedSentences.last?.id {
                            Divider()
                                .background(T.C.divider.opacity(0.6))
                                .padding(.leading, T.S.md)
                        }
                    }
                }
                .card()
            }
        }
    }
    
    @ViewBuilder
    private func savedSentenceRow(_ sentence: Sentence) -> some View {
        ExpandableSentenceCard(
            sentence: sentence, 
            isExpanded: vm.expandedSentenceIds.contains(sentence.id),
            onToggleExpanded: { expanded in
                if expanded {
                    vm.expandedSentenceIds.insert(sentence.id)
                } else {
                    vm.expandedSentenceIds.remove(sentence.id)
                }
            }
        )
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
        VStack(spacing: T.S.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(T.C.accent)
            
            Text("Loading...")
                .foregroundStyle(T.C.ink2)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.C.bg)
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
}

struct ExpandableSentenceCard: View {
    let sentence: Sentence
    let isExpanded: Bool
    let onToggleExpanded: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(sentence.text)
                    .foregroundStyle(T.C.ink)
                    .font(.subheadline)
                    .lineLimit(isExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(T.C.ink2)
                    .font(.system(size: 12))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if !sentence.pinyin.isEmpty {
                        Text(sentence.pinyin.joined(separator: " "))
                            .foregroundStyle(T.C.accent)
                            .font(.caption)
                    }
                    
                    if let english = sentence.english {
                        Text(english)
                            .foregroundStyle(T.C.ink2)
                            .font(.caption)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(.horizontal, T.S.md)
        .padding(.vertical, T.S.md)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                onToggleExpanded(!isExpanded)
            }
        }
    }
}
