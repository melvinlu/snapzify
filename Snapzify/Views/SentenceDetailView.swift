import SwiftUI
import AVKit

struct SentenceDetailView: View {
    let sentence: Sentence
    let document: Document
    @ObservedObject var documentVM: DocumentViewModel
    @StateObject private var sentenceVM: SentenceViewModel
    @State private var showingChatGPTInput = false
    @State private var chatGPTContext = ""
    @State private var frameImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    init(sentence: Sentence, document: Document, documentVM: DocumentViewModel) {
        self.sentence = sentence
        self.document = document
        self.documentVM = documentVM
        self._sentenceVM = StateObject(wrappedValue: documentVM.createSentenceViewModel(for: sentence))
    }
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: T.S.md) {
                // Top: Expanded sentence view
                VStack(alignment: .leading, spacing: T.S.sm) {
                        // Chinese text
                        Text(sentence.text)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(T.C.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Pinyin
                        if !sentenceVM.sentence.pinyin.isEmpty {
                            Text(sentenceVM.sentence.pinyin.joined(separator: " "))
                                .font(.system(size: 16))
                                .foregroundStyle(T.C.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !sentence.pinyin.isEmpty {
                            Text(sentence.pinyin.joined(separator: " "))
                                .font(.system(size: 16))
                                .foregroundStyle(T.C.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // English translation
                        if sentenceVM.isTranslating {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Translating...")
                                    .font(.system(size: 16))
                                    .foregroundStyle(T.C.ink2.opacity(0.7))
                            }
                        } else if let english = sentenceVM.sentence.english ?? sentence.english,
                                  english != "Generating..." {
                            Text(english)
                                .font(.system(size: 18))
                                .foregroundStyle(T.C.ink2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Action buttons
                        HStack(alignment: .center, spacing: 0) {
                            // Pleco button
                            Button {
                                sentenceVM.openInPleco()
                            } label: {
                                Label("Pleco", systemImage: "book")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(PopupButtonStyle())
                            
                            Spacer().frame(width: T.S.sm)
                            
                            // Audio button
                            if sentenceVM.isGeneratingAudio || sentenceVM.isPreparingAudio {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                                        .scaleEffect(0.7)
                                    Text("Load")
                                        .font(.system(size: 14))
                                        .foregroundStyle(T.C.ink2)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(T.C.ink.opacity(0.1))
                                )
                                .fixedSize()
                            } else {
                                Button {
                                    sentenceVM.playOrPauseAudio()
                                } label: {
                                    Label(
                                        sentenceVM.isPlaying ? "Pause" : "Play",
                                        systemImage: sentenceVM.isPlaying ? "pause.fill" : "play.fill"
                                    )
                                    .font(.system(size: 14))
                                }
                                .buttonStyle(PopupButtonStyle(isActive: sentenceVM.isPlaying))
                            }
                            
                            Spacer().frame(width: T.S.sm)
                            
                            // ChatGPT button
                            Button {
                                showingChatGPTInput = true
                            } label: {
                                Label("ChatGPT", systemImage: "message.circle")
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(PopupButtonStyle())
                            
                            Spacer(minLength: 0)
                        }
                        .padding(.top, T.S.sm)
                    }
                    .padding(T.S.lg)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(T.C.card)
                    )
                    .padding(.horizontal, T.S.lg)
                    
                    // Image/Frame section - fit remaining space with proper aspect ratio
                    if document.isVideo {
                        // For video: Show the frame where this text appears
                        if let frameImage = frameImage {
                            ZStack {
                                Image(uiImage: frameImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .overlay(
                                        GeometryReader { imageGeo in
                                            // Calculate the actual displayed image size
                                            let imageSize = frameImage.size
                                            let containerSize = imageGeo.size
                                            let widthScale = containerSize.width / imageSize.width
                                            let heightScale = containerSize.height / imageSize.height
                                            let scale = min(widthScale, heightScale)
                                            let displayWidth = imageSize.width * scale
                                            let displayHeight = imageSize.height * scale
                                            let xOffset = (containerSize.width - displayWidth) / 2
                                            let yOffset = (containerSize.height - displayHeight) / 2
                                            
                                            // Highlight the text area
                                            if let bbox = findBoundingBox() {
                                                Rectangle()
                                                    .stroke(T.C.accent, lineWidth: 3)
                                                    .fill(T.C.accent.opacity(0.2))
                                                    .frame(width: bbox.width * scale,
                                                           height: bbox.height * scale)
                                                    .offset(x: xOffset + bbox.minX * scale,
                                                           y: yOffset + bbox.minY * scale)
                                            }
                                        }
                                    )
                            }
                            .padding(.horizontal, T.S.lg)
                        } else {
                            ProgressView("Loading frame...")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black.opacity(0.2))
                        }
                    } else {
                        // For image: Show the full image with highlighted text
                        if let mediaURL = document.mediaURL,
                           let imageData = try? Data(contentsOf: mediaURL),
                           let uiImage = UIImage(data: imageData) {
                            ZStack {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .overlay(
                                        GeometryReader { imageGeo in
                                            // Calculate the actual displayed image size
                                            let imageSize = uiImage.size
                                            let containerSize = imageGeo.size
                                            let widthScale = containerSize.width / imageSize.width
                                            let heightScale = containerSize.height / imageSize.height
                                            let scale = min(widthScale, heightScale)
                                            let displayWidth = imageSize.width * scale
                                            let displayHeight = imageSize.height * scale
                                            let xOffset = (containerSize.width - displayWidth) / 2
                                            let yOffset = (containerSize.height - displayHeight) / 2
                                            
                                            // Highlight the text area
                                            if let rect = sentence.rangeInImage {
                                                Rectangle()
                                                    .stroke(T.C.accent, lineWidth: 3)
                                                    .fill(T.C.accent.opacity(0.2))
                                                    .frame(width: rect.width * scale,
                                                           height: rect.height * scale)
                                                    .offset(x: xOffset + rect.minX * scale,
                                                           y: yOffset + rect.minY * scale)
                                            }
                                        }
                                    )
                            }
                            .padding(.horizontal, T.S.lg)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(.top, T.S.md)
                .padding(.bottom, T.S.lg)
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false) // Show default back button
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingChatGPTInput) {
            ChatGPTContextInputPopup(
                chineseText: sentence.text,
                context: $chatGPTContext,
                isPresented: $showingChatGPTInput
            )
        }
        .task {
            // Trigger translation if needed
            await sentenceVM.translateIfNeeded()
            
            // Load frame for video
            if document.isVideo {
                await loadVideoFrame()
            }
        }
    }
    
    private func findBoundingBox() -> CGRect? {
        // For videos, find the bounding box from frame appearances
        if let appearances = sentence.frameAppearances, !appearances.isEmpty {
            // Return the first appearance's bbox
            return appearances.first?.bbox
        }
        // For images, use rangeInImage
        return sentence.rangeInImage
    }
    
    private func loadVideoFrame() async {
        guard let mediaURL = document.mediaURL,
              let appearances = sentence.frameAppearances,
              let firstAppearance = appearances.first else { return }
        
        let asset = AVAsset(url: mediaURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        
        let time = CMTime(seconds: firstAppearance.timestamp, preferredTimescale: 600)
        
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            await MainActor.run {
                self.frameImage = UIImage(cgImage: cgImage)
            }
        } catch {
            print("Failed to extract frame: \(error)")
        }
    }
}