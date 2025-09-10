import SwiftUI

struct StreamingTranslationPopup: View {
    let content: String
    let isStreaming: Bool
    let onDismiss: () -> Void
    
    private func parseContent(_ text: String) -> [String] {
        // Simple markdown parser for our specific format
        let lines = text.components(separatedBy: "\n")
        var sections: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                sections.append(trimmed)
            }
        }
        
        return sections
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isStreaming {
                        onDismiss()
                    }
                }
            
            // Popup content
            VStack(spacing: 0) {
                // Header
                HStack {
                    if !isStreaming {
                        Text("Translation")
                            .font(.headline)
                            .foregroundStyle(T.C.ink)
                    }
                    
                    Spacer()
                    
                    if !isStreaming {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(T.C.ink2)
                        }
                    }
                }
                .padding()
                
                if !isStreaming {
                    Divider()
                        .background(T.C.divider)
                }
                
                // Content
                ScrollView {
                    if content.isEmpty && isStreaming {
                        Text("Starting translation...")
                            .font(.body)
                            .foregroundStyle(T.C.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        // Display content with markdown formatting, preserving line breaks
                        VStack(alignment: .leading, spacing: 16) {
                            // Split content by double newlines to separate translations
                            let translations = content.components(separatedBy: "\n\n")
                            
                            ForEach(Array(translations.enumerated()), id: \.offset) { index, translation in
                                if !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    if let attributedString = try? AttributedString(markdown: translation) {
                                        Text(attributedString)
                                            .font(.body)
                                            .foregroundStyle(T.C.ink)
                                    } else {
                                        Text(translation)
                                            .font(.body)
                                            .foregroundStyle(T.C.ink)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                }
                .frame(maxHeight: 400)
                
                // Close button
                if !isStreaming && !content.isEmpty {
                    Divider()
                        .background(T.C.divider)
                    
                    Button {
                        onDismiss()
                    } label: {
                        Text("Close")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(T.C.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(T.C.cardElevated)
                            )
                    }
                    .padding()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(T.C.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(T.C.divider, lineWidth: 1)
            )
            .padding(.horizontal, 30)
            .padding(.vertical, 100)
        }
    }
}