import SwiftUI

struct ReverseSnapzifyView: View {
    @Binding var text: String
    @Binding var translationResult: String
    let isTranslating: Bool
    let onTranslate: () -> Void
    
    // Breakdown properties
    @Binding var breakdownText: String
    @Binding var breakdownResult: String
    let isBreakingDown: Bool
    let onBreakdown: () -> Void
    
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isBreakdownFieldFocused: Bool
    
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
                TextField("Colloquially translate to Chinese...", text: $text)
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
                    Image(systemName: "text.magnifyingglass")
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
                                // Check if this is the main translation line (starts with ** and contains Chinese)
                                if trimmedLine.hasPrefix("**") && containsChineseCharacters(trimmedLine) {
                                    // Extract Chinese characters from the markdown
                                    let cleanedLine = trimmedLine
                                        .replacingOccurrences(of: "**", with: "")
                                        .components(separatedBy: "•")
                                        .first?
                                        .trimmingCharacters(in: .whitespaces) ?? trimmedLine
                                    
                                    // Make the translation itself clickable
                                    Button {
                                        openInPleco(text: cleanedLine)
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
                                }
                                // Check if this line contains Chinese characters for example sentences
                                else if containsChineseCharacters(trimmedLine) && !trimmedLine.hasPrefix("**") {
                                    // Make Chinese example sentences tappable to open in Pleco
                                    Button {
                                        openInPleco(text: trimmedLine)
                                    } label: {
                                        Text(trimmedLine)
                                            .font(.body)
                                            .foregroundStyle(T.C.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    // Regular text (context, dividers, etc.)
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
            
            // Breakdown section
            HStack(spacing: T.S.sm) {
                // Breakdown text field
                TextField("Breakdown Chinese text...", text: $breakdownText)
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
                    .focused($isBreakdownFieldFocused)
                    .onSubmit {
                        onBreakdown()
                        isBreakdownFieldFocused = false
                    }
                
                // Breakdown button
                Button {
                    isBreakdownFieldFocused = false
                    onBreakdown()
                } label: {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd], 
                                         startPoint: .leading, 
                                         endPoint: .trailing)
                        )
                }
                .disabled(breakdownText.isEmpty || isBreakingDown)
            }
            
            // Breakdown results
            if isBreakingDown || !breakdownResult.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Show the text being broken down as header
                    if let currentBreakdown = UserDefaults.standard.string(forKey: "currentBreakdownQuery"), !currentBreakdown.isEmpty {
                        Text(currentBreakdown)
                            .font(.headline)
                            .foregroundStyle(T.C.ink)
                    }
                    
                    if isBreakingDown && breakdownResult.isEmpty {
                        Text("Breaking down text...")
                            .font(.body)
                            .foregroundStyle(T.C.ink2)
                    } else {
                        // Display breakdown results with streaming
                        let lines = breakdownResult.components(separatedBy: "\n")
                        ForEach(lines.indices, id: \.self) { index in
                            let line = lines[index]
                            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                            if !trimmedLine.isEmpty {
                                // Check if line contains Chinese characters to make them tappable
                                if containsChineseCharacters(trimmedLine) {
                                    Button {
                                        // Extract just Chinese characters for Pleco
                                        let chineseOnly = trimmedLine.filter { char in
                                            let scalar = String(char).unicodeScalars.first
                                            if let value = scalar?.value {
                                                return (0x4E00...0x9FFF).contains(value) ||
                                                       (0x3400...0x4DBF).contains(value)
                                            }
                                            return false
                                        }
                                        if !chineseOnly.isEmpty {
                                            openInPleco(text: chineseOnly)
                                        }
                                    } label: {
                                        Text(line)
                                            .font(.body)
                                            .foregroundStyle(T.C.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
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