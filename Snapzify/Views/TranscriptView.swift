import SwiftUI

struct TranscriptView: View {
    let document: Document
    @ObservedObject var documentVM: DocumentViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(getUniqueSentences(), id: \.id) { sentence in
                        NavigationLink(destination: 
                            SentenceDetailView(
                                sentence: sentence,
                                document: document,
                                documentVM: documentVM
                            )
                        ) {
                            TranscriptItemView(sentence: sentence)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
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
    
    var body: some View {
        HStack {
            Text(sentence.text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(T.C.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(T.C.ink2)
        }
        .padding(T.S.md)
        .contentShape(Rectangle())
    }
}

