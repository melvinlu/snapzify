import SwiftUI

// Structure to hold highlight data
struct HighlightRegion: Equatable {
    let id: UUID
    let rect: CGRect
}

// Wrapper that only updates when height changes
struct EquatableImageView: View, Equatable {
    let imageData: Data
    let height: CGFloat
    let showFullScreenImage: () -> Void
    
    static func == (lhs: EquatableImageView, rhs: EquatableImageView) -> Bool {
        // Only re-render if height changes, ignore everything else
        lhs.height == rhs.height
    }
    
    var body: some View {
        ImageSectionView(
            imageData: imageData,
            height: height,
            showFullScreenImage: showFullScreenImage
        )
    }
}

// Separate view for image to prevent re-renders
struct ImageSectionView: View {
    let imageData: Data
    let height: CGFloat
    let showFullScreenImage: () -> Void
    
    var body: some View {
        if let uiImage = UIImage(data: imageData) {
            GeometryReader { geometry in
                ZStack {
                    // Background blur
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: height)
                        .blur(radius: 30)
                        .clipped()
                        .overlay(Color.black.opacity(0.3))
                    
                    // Main image
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: height)
                }
            }
            .frame(height: height)
            .onTapGesture {
                showFullScreenImage()
            }
        }
    }
}

struct DocumentView: View {
    @StateObject var vm: DocumentViewModel
    @State private var showFullScreenImage = false
    @State private var dividerPosition: CGFloat = UIScreen.main.bounds.height * 0.5
    @State private var dragStartPosition: CGFloat = 0
    @State private var isDragging = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                RootBackground {
                    Color.clear
                }
                
                // Image section - positioned at top
                if let imageData = vm.document.imageData,
                   let uiImage = UIImage(data: imageData) {
                    ZStack(alignment: .bottom) {
                        // Static image layer with overlay
                        ZStack {
                            EquatableView(
                                content: EquatableImageView(
                                    imageData: imageData,
                                    height: dividerPosition,
                                    showFullScreenImage: { showFullScreenImage = true }
                                )
                            )
                            
                            // Dynamic highlight overlay for expanded sentences
                            // Place it directly over the image with the same frame calculation
                            GeometryReader { imageGeometry in
                                let expandedRegions = vm.document.sentences
                                    .filter { vm.expandedSentenceIds.contains($0.id) }
                                    .compactMap { sentence -> HighlightRegion? in
                                        guard let rect = sentence.rangeInImage else { return nil }
                                        return HighlightRegion(id: sentence.id, rect: rect)
                                    }
                                
                                let imageAspect = uiImage.size.width / uiImage.size.height
                                let viewAspect = imageGeometry.size.width / imageGeometry.size.height
                                
                                let scale = imageAspect > viewAspect 
                                    ? imageGeometry.size.width / uiImage.size.width
                                    : imageGeometry.size.height / uiImage.size.height
                                    
                                let xOffset = imageAspect > viewAspect
                                    ? 0
                                    : (imageGeometry.size.width - uiImage.size.width * scale) / 2
                                    
                                let yOffset = imageAspect > viewAspect
                                    ? (imageGeometry.size.height - uiImage.size.height * scale) / 2
                                    : 0
                                
                                ForEach(expandedRegions, id: \.id) { region in
                                    Rectangle()
                                        .fill(Color.green.opacity(0.1))
                                        .overlay(
                                            Rectangle()
                                                .strokeBorder(Color.green.opacity(0.5), lineWidth: 1)
                                        )
                                        .frame(
                                            width: region.rect.width * scale,
                                            height: region.rect.height * scale
                                        )
                                        .position(
                                            x: region.rect.midX * scale + xOffset,
                                            y: region.rect.midY * scale + yOffset
                                        )
                                }
                            }
                            .allowsHitTesting(false)
                        }
                        
                        // Action buttons overlay at bottom of image
                        actionButtons
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    .frame(width: geometry.size.width, height: dividerPosition)
                    .clipped()
                    .position(x: geometry.size.width / 2, y: dividerPosition / 2)
                }
                
                // Sentences section - positioned below divider
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: dividerPosition + 30)
                    
                    ZStack(alignment: .top) {
                        // Background for bottom sheet
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(T.C.card.opacity(0.95))
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -5)
                        
                        ScrollView(.vertical) {
                            VStack(spacing: T.S.sm) {
                                // Sentences list
                                sentencesList
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .frame(maxHeight: .infinity)
                }
                
                // Divider - positioned at dividerPosition
                HStack {
                    Spacer()
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(isDragging ? T.C.accent : T.C.ink2.opacity(0.5))
                            .frame(width: 40, height: 4)
                        Capsule()
                            .fill(isDragging ? T.C.accent : T.C.ink2.opacity(0.5))
                            .frame(width: 40, height: 4)
                    }
                    Spacer()
                }
                .frame(width: geometry.size.width, height: 30) // Taller with full width hitbox
                .contentShape(Rectangle())
                .position(x: geometry.size.width / 2, y: dividerPosition + 15)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                dragStartPosition = dividerPosition
                            }
                            let newPosition = dragStartPosition + value.translation.height
                            dividerPosition = min(max(newPosition, geometry.size.height * 0.2), geometry.size.height * 0.8)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(documentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showFullScreenImage) {
            if let imageData = vm.document.imageData, let uiImage = UIImage(data: imageData) {
                FullScreenImageView(image: uiImage, isPresented: $showFullScreenImage)
            }
        }
        .alert("Delete Document", isPresented: $vm.showDeleteImageAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                vm.deleteImage()
            }
        } message: {
            Text("This will delete the document from Snapzify AND permanently delete the original photo from your device's photo library. This action cannot be undone.")
        }
        .task {
            await vm.translateAllPending()
        }
        .task {
            // Start refresh timer if any sentences are still generating
            let hasGenerating = vm.document.sentences.contains { sentence in
                sentence.english == "Generating..."
            }
            if hasGenerating {
                vm.startRefreshTimer()
            }
        }
        .onChange(of: vm.shouldDismiss) { shouldDismiss in
            if shouldDismiss {
                dismiss()
            }
        }
    }
    
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: T.S.sm) {
            Button {
                vm.toggleExpandAll()
            } label: {
                Image(systemName: vm.areAllExpanded ? "arrow.up.and.down.and.arrow.left.and.right" : "arrow.down.left.and.arrow.up.right")
                    .foregroundStyle(T.C.ink)
                    .frame(width: 36, height: 36)
                    .background(T.C.card.opacity(0.95))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Button {
                vm.toggleImageSave()
            } label: {
                Image(systemName: vm.document.isSaved ? "pin.fill" : "pin")
                    .foregroundStyle(vm.document.isSaved ? T.C.accent : T.C.ink)
                    .frame(width: 36, height: 36)
                    .background(T.C.card.opacity(0.95))
                    .clipShape(Circle())
            }
            
            // Only show delete button if we have an asset identifier (photo from "Most Recent")
            if vm.document.assetIdentifier != nil {
                Button {
                    vm.showDeleteImageAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .background(T.C.card.opacity(0.95))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    
    @ViewBuilder
    private var sentencesList: some View {
        VStack(spacing: T.S.sm) {
            ForEach(vm.document.sentences) { sentence in
                SentenceRowView(
                    vm: vm.createSentenceViewModel(for: sentence)
                )
                .id(sentence.id) // Use stable ID to prevent view recreation
            }
        }
    }
    
    private var documentTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: vm.document.createdAt)
    }
}

struct FullScreenImageView: View {
    let image: UIImage
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea(.all)
            
            VStack {
                HStack {
                    Spacer()
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                    .padding()
                }
                
                Spacer()
                
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height + dragOffset.height)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                            lastScale = 1.0
                                        }
                                    } else if scale > 5.0 {
                                        withAnimation {
                                            scale = 5.0
                                            lastScale = 5.0
                                        }
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        // When zoomed in, use drag for panning
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    } else {
                                        // When not zoomed, use vertical drag for dismissal
                                        if value.translation.height > 0 {
                                            dragOffset = value.translation
                                            backgroundOpacity = 1.0 - (value.translation.height / 500.0)
                                        }
                                    }
                                }
                                .onEnded { value in
                                    if scale > 1.0 {
                                        // When zoomed in, save pan offset
                                        lastOffset = offset
                                    } else {
                                        // When not zoomed, check for dismissal
                                        if value.translation.height > 150 {
                                            isPresented = false
                                        } else {
                                            withAnimation(.spring()) {
                                                dragOffset = .zero
                                                backgroundOpacity = 1.0
                                            }
                                        }
                                        
                                        // Reset offsets when at normal scale
                                        if scale <= 1.0 {
                                            withAnimation {
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    }
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale == 1.0 {
                                scale = 2.0
                                lastScale = 2.0
                            } else {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
                
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}