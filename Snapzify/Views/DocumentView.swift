import SwiftUI

struct DocumentView: View {
    @StateObject var vm: DocumentViewModel
    @State private var showFullScreenImage = false
    
    var body: some View {
        RootBackground {
            ScrollView {
                VStack(spacing: T.S.md) {
                    if vm.showOriginalImage, let imageData = vm.document.imageData {
                        imageSection(imageData: imageData)
                    }
                    
                    imageToggle
                    
                    
                    sentencesList
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(documentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showFullScreenImage) {
            if let imageData = vm.document.imageData, let uiImage = UIImage(data: imageData) {
                FullScreenImageView(image: uiImage, isPresented: $showFullScreenImage)
            }
        }
        .task {
            await vm.translateAllPending()
        }
    }
    
    @ViewBuilder
    private func imageSection(imageData: Data) -> some View {
        if let uiImage = UIImage(data: imageData) {
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width)
                    
                    if let selectedId = vm.selectedSentenceId,
                       let region = vm.highlightedRegion(for: selectedId) {
                        highlightOverlay(region: region, imageSize: uiImage.size, viewSize: geometry.size)
                    }
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(T.C.outline, lineWidth: 1)
            )
            .transition(.asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity),
                removal: .scale(scale: 0.95).combined(with: .opacity)
            ))
            .onTapGesture {
                showFullScreenImage = true
            }
        }
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
    private var imageToggle: some View {
        HStack(spacing: T.S.sm) {
            Button {
                vm.toggleImageVisibility()
            } label: {
                HStack {
                    Image(systemName: vm.showOriginalImage ? "eye.slash" : "eye")
                    Text(vm.showOriginalImage ? "Hide" : "Show")
                        .font(.subheadline)
                }
                .foregroundStyle(T.C.ink2)
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(T.C.card.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button {
                vm.toggleExpandAll()
            } label: {
                HStack {
                    Image(systemName: vm.areAllExpanded ? "arrow.up.and.down.and.arrow.left.and.right" : "arrow.down.left.and.arrow.up.right")
                    Text(vm.areAllExpanded ? "Collapse" : "Expand")
                        .font(.subheadline)
                }
                .foregroundStyle(T.C.ink2)
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(T.C.card.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button {
                vm.toggleImageSave()
            } label: {
                Image(systemName: vm.document.isSaved ? "pin.fill" : "pin")
                    .foregroundStyle(vm.document.isSaved ? T.C.ink : T.C.ink2)
                    .frame(height: 32)
                    .padding(.horizontal, 12)
                    .background(T.C.card.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
    
    var body: some View {
        ZStack {
            Color.black
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
                    .offset(offset)
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
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                    if scale <= 1.0 {
                                        withAnimation {
                                            offset = .zero
                                            lastOffset = .zero
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