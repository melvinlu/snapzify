import SwiftUI

struct DocumentView: View {
    @StateObject var vm: DocumentViewModel
    
    var body: some View {
        RootBackground {
            ScrollView {
                VStack(spacing: T.S.md) {
                    if vm.showOriginalImage, let imageData = vm.document.imageData {
                        imageSection(imageData: imageData)
                    }
                    
                    imageToggle
                    
                    if vm.isTranslatingBatch {
                        translationProgress
                    }
                    
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
                    Text(vm.showOriginalImage ? "Hide Original" : "Show Original")
                        .font(.subheadline)
                }
                .foregroundStyle(T.C.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(T.C.card.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button {
                vm.toggleImagePin()
            } label: {
                Image(systemName: vm.document.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(vm.document.isPinned ? T.C.ink : T.C.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(T.C.card.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button {
                vm.toggleImageSave()
            } label: {
                Image(systemName: vm.document.isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(vm.document.isSaved ? T.C.ink : T.C.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(T.C.card.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    @ViewBuilder
    private var translationProgress: some View {
        HStack(spacing: T.S.xs) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                .scaleEffect(0.8)
            
            Text("Translating sentences...")
                .font(.subheadline)
                .foregroundStyle(T.C.ink2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(T.C.card.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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