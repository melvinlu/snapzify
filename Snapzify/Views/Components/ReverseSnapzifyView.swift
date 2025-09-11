import SwiftUI

struct ReverseSnapzifyView: View {
    // Unified translation properties
    @Binding var translateText: String
    @Binding var translationResult: String
    @Binding var translationFollowUp: String
    let isProcessing: Bool
    let onTranslate: () -> Void
    let onTranslationFollowUp: () -> Void
    @Binding var isTranslationExpanded: Bool
    
    // Ask properties (keeping as separate feature)
    @Binding var askText: String
    @Binding var askResult: String
    @Binding var askFollowUp: String
    let isAsking: Bool
    let onAsk: () -> Void
    let onAskFollowUp: () -> Void
    @Binding var isAskExpanded: Bool
    
    @FocusState private var isTranslateFieldFocused: Bool
    @FocusState private var isAskFieldFocused: Bool
    @FocusState private var isTranslationFollowUpFieldFocused: Bool
    @FocusState private var isAskFollowUpFieldFocused: Bool
    
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
            // Unified translation/breakdown textbox
            HStack(spacing: T.S.sm) {
                TextField("Translate...", text: $translateText)
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
                    .focused($isTranslateFieldFocused)
                    .onSubmit {
                        if !translateText.isEmpty {
                            onTranslate()
                            isTranslateFieldFocused = false
                        }
                    }
                
                Button {
                    isTranslateFieldFocused = false
                    onTranslate()
                } label: {
                    Image(systemName: "character.book.closed.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                }
                .disabled(translateText.isEmpty || isProcessing)
            }
            
            // Translation/Breakdown results
            if isProcessing || !translationResult.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Header with collapse button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isTranslationExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Translation")
                                .font(.headline)
                                .foregroundStyle(T.C.ink)
                            
                            Spacer()
                            
                            Image(systemName: isTranslationExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(T.C.ink2)
                                .rotationEffect(.degrees(isTranslationExpanded ? 0 : -90))
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isTranslationExpanded)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Show header based on what was processed
                        if let currentTranslation = UserDefaults.standard.string(forKey: "currentTranslationQuery"), !currentTranslation.isEmpty {
                            Text(currentTranslation)
                                .font(.headline)
                                .foregroundStyle(T.C.ink)
                        } else if let currentBreakdown = UserDefaults.standard.string(forKey: "currentBreakdownQuery"), !currentBreakdown.isEmpty {
                            // Extract only Chinese characters for Pleco
                            let chineseOnly = currentBreakdown.filter { char in
                                let scalar = String(char).unicodeScalars.first
                                if let value = scalar?.value {
                                    return (0x4E00...0x9FFF).contains(value) ||
                                    (0x3400...0x4DBF).contains(value) ||
                                    (0x20000...0x2A6DF).contains(value)
                                }
                                return false
                            }
                            
                            Button {
                                openInPleco(text: chineseOnly.isEmpty ? currentBreakdown : chineseOnly)
                            } label: {
                                Text(currentBreakdown)
                                    .font(.headline)
                                    .foregroundStyle(T.C.ink)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if isProcessing && translationResult.isEmpty {
                            Text("Processing...")
                                .font(.body)
                                .foregroundStyle(T.C.ink2)
                        } else {
                            // Display results
                            let lines = translationResult.components(separatedBy: "\n")
                            ForEach(lines.indices, id: \.self) { index in
                                let line = lines[index]
                                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                                if !trimmedLine.isEmpty {
                                    // Check if this is a Chinese translation result (starts with ** and contains Chinese)
                                    if trimmedLine.hasPrefix("**") && containsChineseCharacters(trimmedLine) {
                                        let cleanedLine = trimmedLine
                                            .replacingOccurrences(of: "**", with: "")
                                            .components(separatedBy: "•")
                                            .first?
                                            .trimmingCharacters(in: .whitespaces) ?? trimmedLine
                                        
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
                                    // Check for lines with bullet points (character breakdowns)
                                    else if trimmedLine.contains("•") && containsChineseCharacters(trimmedLine) {
                                        let components = trimmedLine.components(separatedBy: "•")
                                        HStack(spacing: 4) {
                                            ForEach(components.indices, id: \.self) { compIndex in
                                                let component = components[compIndex].trimmingCharacters(in: .whitespaces)
                                                if compIndex == 0 && containsChineseCharacters(component) {
                                                    // Extract only Chinese characters
                                                    let chineseOnly = component.filter { char in
                                                        let scalar = String(char).unicodeScalars.first
                                                        if let value = scalar?.value {
                                                            return (0x4E00...0x9FFF).contains(value) ||
                                                            (0x3400...0x4DBF).contains(value) ||
                                                            (0x20000...0x2A6DF).contains(value)
                                                        }
                                                        return false
                                                    }
                                                    
                                                    Button {
                                                        openInPleco(text: chineseOnly.isEmpty ? component : chineseOnly)
                                                    } label: {
                                                        Text(component)
                                                            .font(.body)
                                                            .foregroundStyle(T.C.ink)
                                                    }
                                                    .buttonStyle(.plain)
                                                    
                                                    if compIndex < components.count - 1 {
                                                        Text(" • ")
                                                            .font(.body)
                                                            .foregroundStyle(T.C.ink2)
                                                    }
                                                } else {
                                                    Text(component)
                                                        .font(.body)
                                                        .foregroundStyle(T.C.ink)
                                                    
                                                    if compIndex < components.count - 1 {
                                                        Text(" • ")
                                                            .font(.body)
                                                            .foregroundStyle(T.C.ink2)
                                                    }
                                                }
                                            }
                                            Spacer()
                                        }
                                    }
                                    // Chinese sentences or overall meanings
                                    else if containsChineseCharacters(trimmedLine) {
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
                                        // Regular text
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
                        
                        // Follow-up textbox
                        if !isProcessing && !translationResult.isEmpty {
                            HStack(spacing: T.S.sm) {
                                TextField("Follow up...", text: $translationFollowUp)
                                    .textFieldStyle(.plain)
                                    .font(.body)
                                    .foregroundStyle(T.C.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(T.C.card.opacity(0.5))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(T.C.divider, lineWidth: 1)
                                    )
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.go)
                                    .focused($isTranslationFollowUpFieldFocused)
                                    .onSubmit {
                                        if !translationFollowUp.isEmpty {
                                            onTranslationFollowUp()
                                            isTranslationFollowUpFieldFocused = false
                                        }
                                    }
                                
                                Button {
                                    isTranslationFollowUpFieldFocused = false
                                    onTranslationFollowUp()
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(
                                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd],
                                                           startPoint: .leading,
                                                           endPoint: .trailing)
                                        )
                                }
                                .disabled(translationFollowUp.isEmpty || isProcessing)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .frame(maxHeight: isTranslationExpanded ? .infinity : 0)
                    .clipped()
                    .opacity(isTranslationExpanded ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: isTranslationExpanded)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(T.C.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(T.C.divider, lineWidth: 1)
                )
            }
            
            // Ask section
            HStack(spacing: T.S.sm) {
                TextField("Ask...", text: $askText)
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
                    .focused($isAskFieldFocused)
                    .onSubmit {
                        if !askText.isEmpty {
                            onAsk()
                            isAskFieldFocused = false
                        }
                    }
                
                Button {
                    isAskFieldFocused = false
                    onAsk()
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd],
                                           startPoint: .leading,
                                           endPoint: .trailing)
                        )
                }
                .disabled(askText.isEmpty || isAsking)
            }
            
            // Ask results
            if isAsking || !askResult.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Header with collapse button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isAskExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Ask")
                                .font(.headline)
                                .foregroundStyle(T.C.ink)
                            
                            Spacer()
                            
                            Image(systemName: isAskExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(T.C.ink2)
                                .rotationEffect(.degrees(isAskExpanded ? 0 : -90))
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isAskExpanded)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        if let currentAsk = UserDefaults.standard.string(forKey: "currentAskQuery"), !currentAsk.isEmpty {
                            Text(currentAsk)
                                .font(.headline)
                                .foregroundStyle(T.C.ink)
                        }
                        
                        if isAsking && askResult.isEmpty {
                            Text("Asking...")
                                .font(.body)
                                .foregroundStyle(T.C.ink2)
                        } else {
                            let lines = askResult.components(separatedBy: "\n")
                            ForEach(lines.indices, id: \.self) { index in
                                let line = lines[index]
                                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                                if !trimmedLine.isEmpty {
                                    if containsChineseCharacters(trimmedLine) {
                                        // Extract only Chinese characters for Pleco
                                        let chineseOnly = trimmedLine.filter { char in
                                            let scalar = String(char).unicodeScalars.first
                                            if let value = scalar?.value {
                                                return (0x4E00...0x9FFF).contains(value) ||
                                                (0x3400...0x4DBF).contains(value) ||
                                                (0x20000...0x2A6DF).contains(value)
                                            }
                                            return false
                                        }
                                        
                                        Button {
                                            openInPleco(text: chineseOnly.isEmpty ? trimmedLine : chineseOnly)
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
                        
                        // Follow-up textbox for Ask
                        if !isAsking && !askResult.isEmpty {
                            HStack(spacing: T.S.sm) {
                                TextField("Follow up...", text: $askFollowUp)
                                    .textFieldStyle(.plain)
                                    .font(.body)
                                    .foregroundStyle(T.C.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(T.C.card.opacity(0.5))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(T.C.divider, lineWidth: 1)
                                    )
                                    .autocorrectionDisabled(true)
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.go)
                                    .focused($isAskFollowUpFieldFocused)
                                    .onSubmit {
                                        if !askFollowUp.isEmpty {
                                            onAskFollowUp()
                                            isAskFollowUpFieldFocused = false
                                        }
                                    }
                                
                                Button {
                                    isAskFollowUpFieldFocused = false
                                    onAskFollowUp()
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(
                                            LinearGradient(colors: [T.C.brandStart, T.C.brandEnd],
                                                           startPoint: .leading,
                                                           endPoint: .trailing)
                                        )
                                }
                                .disabled(askFollowUp.isEmpty || isAsking)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .frame(maxHeight: isAskExpanded ? .infinity : 0)
                    .clipped()
                    .opacity(isAskExpanded ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: isAskExpanded)
                }
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
