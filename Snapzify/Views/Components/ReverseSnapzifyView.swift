import SwiftUI

struct ReverseSnapzifyView: View {
    @Binding var text: String
    @Binding var translationResult: String
    let isTranslating: Bool
    let onTranslate: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: T.S.sm) {
            HStack(spacing: T.S.sm) {
                // Text field
                TextField("To colloquially translate...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(T.C.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(T.C.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(T.C.divider, lineWidth: 1)
                    )
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        onTranslate()
                        isTextFieldFocused = false
                    }
                
                // Translate button
                Button {
                    isTextFieldFocused = false
                    onTranslate()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd], 
                                         startPoint: .leading, 
                                         endPoint: .trailing)
                        )
                }
                .disabled(text.isEmpty || isTranslating)
            }
            
            // Translation results
            if isTranslating || !translationResult.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Show the word/phrase being translated as header
                    if let currentTranslation = UserDefaults.standard.string(forKey: "currentTranslationQuery"), !currentTranslation.isEmpty {
                        Text(currentTranslation)
                            .font(.headline)
                            .foregroundStyle(T.C.ink)
                    }
                    
                    if isTranslating && translationResult.isEmpty {
                        Text("Reverse Snapzifying...")
                            .font(.body)
                            .foregroundStyle(T.C.ink2)
                    } else {
                        // Same display for both streaming and completed
                        let lines = translationResult.components(separatedBy: "\n")
                        ForEach(lines.indices, id: \.self) { index in
                            let line = lines[index]
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                // Check if this line contains Chinese characters for Pleco link
                                if containsChineseCharacters(trimmedLine) && !trimmedLine.hasPrefix("**") {
                                    // Make Chinese sentences tappable to open in Pleco
                                    Button {
                                        openInPleco(text: trimmedLine)
                                    } label: {
                                        if let attributedString = try? AttributedString(markdown: line) {
                                            Text(attributedString)
                                                .font(.body)
                                                .foregroundStyle(T.C.ink)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            Text(line)
                                                .font(.body)
                                                .foregroundStyle(T.C.ink)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    // Regular text with markdown
                                    if let attributedString = try? AttributedString(markdown: line) {
                                        Text(attributedString)
                                            .font(.body)
                                            .foregroundStyle(T.C.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Text(line)
                                            .font(.body)
                                            .foregroundStyle(T.C.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(T.C.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(T.C.divider, lineWidth: 1)
                )
            }
        }
    }
}