import SwiftUI

struct TranscriptView: View {
    let document: Document
    @ObservedObject var documentVM: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(getUniqueSentences(), id: \.id) { sentence in
                    ExpandedSentenceView(
                        sentence: sentence,
                        sentenceVM: documentVM.createSentenceViewModel(for: sentence)
                    )
                    
                    // Divider between sentences
                    if sentence.id != getUniqueSentences().last?.id {
                        Divider()
                            .background(T.C.divider.opacity(0.3))
                            .padding(.horizontal, T.S.md)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(T.C.card)
            )
            .padding(.horizontal, T.S.lg)
            .padding(.vertical, T.S.md)
        }
        .background(Color.black)
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
    
    private func getUniqueSentences() -> [Sentence] {
        // For videos, deduplicate sentences that appear in multiple frames
        if document.isVideo {
            var seenTexts = Set<String>()
            var uniqueSentences: [Sentence] = []
            
            for sentence in document.sentences {
                if !seenTexts.contains(sentence.text) {
                    seenTexts.insert(sentence.text)
                    uniqueSentences.append(sentence)
                }
            }
            
            return uniqueSentences
        } else {
            // For images, return all sentences as-is
            return document.sentences
        }
    }
}

struct ExpandedSentenceView: View {
    let sentence: Sentence
    @ObservedObject var sentenceVM: SentenceViewModel
    @State private var showingChatGPTInput = false
    @State private var chatGPTContext = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            // Chinese text
            Text(sentence.text)
                .font(.system(size: 20, weight: .semibold))
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
            
            // English translation or loading indicator
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
                    .font(.system(size: 16))
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
                        .font(.system(size: 13))
                }
                .buttonStyle(TranscriptButtonStyle())
                
                Spacer().frame(width: T.S.sm)
                
                // Audio button
                if sentenceVM.isGeneratingAudio || sentenceVM.isPreparingAudio {
                    HStack(spacing: 4) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                            .scaleEffect(0.6)
                        Text("Load")
                            .font(.system(size: 13))
                            .foregroundStyle(T.C.ink2)
                            .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
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
                        .font(.system(size: 13))
                    }
                    .buttonStyle(TranscriptButtonStyle(isActive: sentenceVM.isPlaying))
                }
                
                Spacer().frame(width: T.S.sm)
                
                // ChatGPT button
                Button {
                    showingChatGPTInput = true
                } label: {
                    Label("ChatGPT", systemImage: "message.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(TranscriptButtonStyle())
                
                Spacer(minLength: 0)
            }
            .padding(.top, T.S.xs)
        }
        .padding(T.S.md)
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
        }
    }
}

struct TranscriptButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .white : T.C.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? T.C.accent : T.C.ink.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

