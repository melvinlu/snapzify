import SwiftUI

struct TranscriptView: View {
    let document: Document
    @ObservedObject var documentVM: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedSentences: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(getUniqueSentences(), id: \.id) { sentence in
                        TranscriptItemView(
                            sentence: sentence,
                            documentVM: documentVM,
                            isExpanded: expandedSentences.contains(sentence.id),
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedSentences.contains(sentence.id) {
                                        expandedSentences.remove(sentence.id)
                                    } else {
                                        expandedSentences.insert(sentence.id)
                                        // Trigger translation if needed
                                        let sentenceVM = documentVM.createSentenceViewModel(for: sentence)
                                        Task {
                                            await sentenceVM.translateIfNeeded()
                                        }
                                    }
                                }
                            }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .foregroundStyle(T.C.accent)
                    }
                }
            }
        }
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

struct TranscriptItemView: View {
    let sentence: Sentence
    let documentVM: DocumentViewModel
    let isExpanded: Bool
    let onTap: () -> Void
    
    @StateObject private var sentenceVM: SentenceViewModel
    @State private var showingChatGPTInput = false
    @State private var chatGPTContext = ""
    
    init(sentence: Sentence, documentVM: DocumentViewModel, isExpanded: Bool, onTap: @escaping () -> Void) {
        self.sentence = sentence
        self.documentVM = documentVM
        self.isExpanded = isExpanded
        self.onTap = onTap
        self._sentenceVM = StateObject(wrappedValue: documentVM.createSentenceViewModel(for: sentence))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: T.S.sm) {
                    // Always show Chinese text
                    Text(sentence.text)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(T.C.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Show translations and actions when expanded
                    if isExpanded {
                        VStack(alignment: .leading, spacing: T.S.sm) {
                            // Pinyin
                            if !sentenceVM.sentence.pinyin.isEmpty {
                                Text(sentenceVM.sentence.pinyin.joined(separator: " "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(T.C.ink2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else if !sentence.pinyin.isEmpty {
                                Text(sentence.pinyin.joined(separator: " "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(T.C.ink2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            // English translation
                            if sentenceVM.isTranslating {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Translating...")
                                        .font(.system(size: 14))
                                        .foregroundStyle(T.C.ink2.opacity(0.7))
                                }
                            } else if let english = sentenceVM.sentence.english ?? sentence.english, 
                                      english != "Generating..." {
                                Text(english)
                                    .font(.system(size: 16))
                                    .foregroundStyle(T.C.ink2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            // Action buttons
                            HStack(alignment: .center, spacing: 0) {
                                // Pleco button
                                Button {
                                    sentenceVM.openInPleco()
                                } label: {
                                    Label("Pleco", systemImage: "book")
                                        .font(.caption)
                                }
                                .buttonStyle(PopupButtonStyle())
                                
                                // Spacing after Pleco
                                Spacer().frame(width: T.S.sm)
                                
                                // Audio button
                                if sentenceVM.isGeneratingAudio || sentenceVM.isPreparingAudio {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                                            .scaleEffect(0.6)
                                        Text("Load")
                                            .font(.caption)
                                            .foregroundStyle(T.C.ink2)
                                            .fixedSize()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
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
                                        .font(.caption)
                                    }
                                    .buttonStyle(PopupButtonStyle(isActive: sentenceVM.isPlaying))
                                }
                                
                                // Spacing after Audio
                                Spacer().frame(width: T.S.sm)
                                
                                // ChatGPT button
                                Button {
                                    showingChatGPTInput = true
                                } label: {
                                    Label("ChatGPT", systemImage: "message.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(PopupButtonStyle())
                                
                                // Push remaining space
                                Spacer(minLength: 0)
                            }
                            .padding(.top, T.S.xs)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(T.S.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showingChatGPTInput) {
            ChatGPTContextInputPopup(
                chineseText: sentence.text,
                context: $chatGPTContext,
                isPresented: $showingChatGPTInput
            )
        }
    }
}

