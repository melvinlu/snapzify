import SwiftUI
import UIKit

struct StreamingTranslationPopup: View {
    let content: String
    let isStreaming: Bool
    let onDismiss: () -> Void
    
    private func containsChineseCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for CJK Unified Ideographs range
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) ||
               (0x2A700...0x2B73F).contains(scalar.value) ||
               (0x2B740...0x2B81F).contains(scalar.value) ||
               (0x2B820...0x2CEAF).contains(scalar.value) ||
               (0x2CEB0...0x2EBEF).contains(scalar.value) ||
               (0x30000...0x3134F).contains(scalar.value) {
                return true
            }
        }
        return false
    }
    
    private func openInPleco(text: String) {
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "plecoapi://x-callback-url/s?q=\(encodedText)") else {
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
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
                                    VStack(alignment: .leading, spacing: 4) {
                                        // Parse each translation block
                                        let lines = translation.components(separatedBy: "\n")
                                        ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                                            if !trimmedLine.isEmpty {
                                                // Check if this line looks like a Chinese example sentence
                                                // (doesn't start with ** and contains Chinese characters)
                                                if lineIndex == lines.count - 1 && 
                                                   !trimmedLine.hasPrefix("**") &&
                                                   containsChineseCharacters(trimmedLine) {
                                                    // Make example sentence tappable to open in Pleco
                                                    Button {
                                                        openInPleco(text: trimmedLine)
                                                    } label: {
                                                        if let attributedString = try? AttributedString(markdown: line) {
                                                            Text(attributedString)
                                                                .font(.body)
                                                                .foregroundStyle(Color.blue)
                                                                .underline()
                                                        } else {
                                                            Text(line)
                                                                .font(.body)
                                                                .foregroundStyle(Color.blue)
                                                                .underline()
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                } else {
                                                    // Regular text
                                                    if let attributedString = try? AttributedString(markdown: line) {
                                                        Text(attributedString)
                                                            .font(.body)
                                                            .foregroundStyle(T.C.ink)
                                                    } else {
                                                        Text(line)
                                                            .font(.body)
                                                            .foregroundStyle(T.C.ink)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                }
                .frame(height: 500)
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