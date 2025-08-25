import SwiftUI

struct DocumentView: View {
    @StateObject var vm: DocumentViewModel
    @State private var showFullScreenImage = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            RootBackground {
                VStack(spacing: 0) {
                    // Top 50%: Fixed image section
                    ZStack(alignment: .bottom) {
                        if let imageData = vm.document.imageData {
                            imageSection(imageData: imageData, height: geometry.size.height * 0.5)
                        }
                        
                        // Action buttons overlay at bottom of image
                        actionButtons
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    .frame(height: geometry.size.height * 0.5)
                    
                    // Bottom 50%: Scrollable sentences list
                    ZStack(alignment: .top) {
                        // Background for bottom sheet
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(T.C.card.opacity(0.95))
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -5)
                        
                        ScrollView(.vertical) {
                            VStack(spacing: T.S.sm) {
                                // Handle bar indicator
                                Capsule()
                                    .fill(T.C.ink2.opacity(0.3))
                                    .frame(width: 36, height: 5)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                                
                                // Sentences list
                                sentencesList
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 20)
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .frame(height: geometry.size.height * 0.5)
                }
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
    private func imageSection(imageData: Data, height: CGFloat) -> some View {
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
                    
                    if let selectedId = vm.selectedSentenceId,
                       let region = vm.highlightedRegion(for: selectedId) {
                        let imageDisplaySize = calculateImageDisplaySize(imageSize: uiImage.size, viewSize: CGSize(width: geometry.size.width, height: height))
                        highlightOverlay(region: region, imageSize: uiImage.size, viewSize: imageDisplaySize)
                    }
                }
            }
            .frame(height: height)
            .onTapGesture {
                showFullScreenImage = true
            }
        }
    }
    
    private func calculateImageDisplaySize(imageSize: CGSize, viewSize: CGSize) -> CGSize {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
    
    @ViewBuilder
    private func highlightOverlay(region: CGRect, imageSize: CGSize, viewSize: CGSize) -> some View {
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledRect = CGRect(
            x: region.origin.x * scale,
            y: region.origin.y * scale,
            width: region.width * scale,
            height: region.height * scale
        )
        
        Rectangle()
            .fill(T.C.accent.opacity(0.2))
            .overlay(
                Rectangle()
                    .stroke(T.C.accent, lineWidth: 2)
            )
            .frame(width: scaledRect.width, height: scaledRect.height)
            .position(x: scaledRect.midX, y: scaledRect.midY)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: region)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: T.S.sm) {
            Button {
                vm.toggleExpandAll()
            } label: {
                HStack {
                    Image(systemName: vm.areAllExpanded ? "arrow.up.and.down.and.arrow.left.and.right" : "arrow.down.left.and.arrow.up.right")
                    Text(vm.areAllExpanded ? "Collapse All" : "Expand All")
                        .font(.subheadline)
                }
                .foregroundStyle(T.C.ink)
                .frame(height: 36)
                .padding(.horizontal, 12)
                .background(T.C.card.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .onTapGesture {
                    vm.selectSentence(sentence.id)
                }
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
