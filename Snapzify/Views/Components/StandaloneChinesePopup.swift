import SwiftUI

// MARK: - Standalone Chinese Popup
// Reusable popup component for displaying Chinese text with full interaction capabilities
// Based on SelectedSentencePopup but works without Document/Sentence context
struct StandaloneChinesePopup: View {
    let chineseText: String
    @Binding var isShowing: Bool
    let position: CGPoint
    
    @State private var chatGPTBreakdown = ""
    @State private var isLoadingBreakdown = false
    @State private var breakdownTask: Task<Void, Never>?
    @State private var selectedWords: [String] = []
    @State private var characterAnalyses: [String: String] = [:]
    @State private var isLoadingCharacter = false
    @State private var characterTask: Task<Void, Never>?
    @State private var showAllBreakdowns = false
    @State private var isLoadingAllBreakdowns = false
    @State private var isPlaying = false
    @State private var isGeneratingAudio = false
    @State private var audioAsset: AudioAsset?
    
    private let chatGPTService = ServiceContainer.shared.chatGPTService
    private let ttsService = ServiceContainer.shared.ttsService
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(alignment: .center, spacing: 0) {
            // Pleco button
            Button {
                openInPleco()
            } label: {
                Image(systemName: "book")
                    .font(.system(size: 16))
            }
            .buttonStyle(StandalonePopupButtonStyle())
            
            // Spacing after Pleco
            Spacer().frame(width: T.S.sm)
            
            // Audio button
            if isGeneratingAudio {
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
                    playOrPauseAudio()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(StandalonePopupButtonStyle(isActive: isPlaying))
            }
            
            // Removed All Characters button - automatic breakdown in prompt instead
            
            // Push remaining space
            Spacer(minLength: 0)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Chinese text at top
            TappableCharactersView(
                text: chineseText,
                selectedWords: $selectedWords,
                onCharacterTap: { char, position in
                    loadCharacterAnalysis(for: char, at: position)
                }
            )
            .padding(T.S.lg)
            
            // Scrollable middle section for translation and breakdowns
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: T.S.sm) {
                    // Always show sentence translation first
                    if chatGPTBreakdown.isEmpty && isLoadingBreakdown {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Translating...")
                                .font(.system(size: 14))
                                .foregroundStyle(T.C.ink2)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    } else if !chatGPTBreakdown.isEmpty {
                        Text(chatGPTBreakdown)
                            .font(.system(size: 14))
                            .foregroundStyle(T.C.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                    }
                    
                    // Show character/word analyses below if any characters are selected
                    if !selectedWords.isEmpty || isLoadingCharacter {
                        Divider()
                            .padding(.vertical, 4)
                        
                        // Character analyses
                        ForEach(selectedWords, id: \.self) { word in
                            if let analysis = characterAnalyses[word] {
                                VStack(alignment: .leading, spacing: 2) {
                                    // Parse the analysis
                                    let lines = analysis.split(separator: "\n")
                                        .map { $0.trimmingCharacters(in: .whitespaces) }
                                        .filter { !$0.isEmpty }
                                    
                                    // Format main word/character breakdown
                                    if lines.count >= 2 {
                                        // Main word: pinyin, definition with role
                                        let mainText = "\(word): \(lines[0]), \(lines[1])"
                                        Text(mainText)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(T.C.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        // Only show individual character breakdowns for multi-character words
                                        if word.count > 1 && lines.count > 2 {
                                            ForEach(Array(lines.dropFirst(2)), id: \.self) { charLine in
                                                CharacterBreakdownLineView(charLine: charLine)
                                            }
                                        }
                                    } else {
                                        // Fallback for single line or unexpected format
                                        Text("\(word): \(analysis)")
                                            .font(.system(size: 13))
                                            .foregroundStyle(T.C.ink2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                            }
                        }
                        
                        // Show loading indicator if analyzing
                        if isLoadingCharacter {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Analyzing...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(T.C.ink2)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, T.S.lg)
                .padding(.vertical, T.S.sm)
            }
            .frame(maxHeight: .infinity)
            .scrollIndicators(.visible, axes: .vertical)
            
            // Action buttons anchored at bottom
            actionButtons
                .padding(T.S.lg)
        }
        .frame(minHeight: 250, maxHeight: 400)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .compositingGroup() // Ensures the view is rendered as a single opaque unit
        .onAppear {
            // Clear all state when popup appears
            selectedWords.removeAll()
            characterAnalyses.removeAll()
            chatGPTBreakdown = ""
            isLoadingCharacter = false
            showAllBreakdowns = false
            isLoadingAllBreakdowns = false
            characterTask?.cancel()
            breakdownTask?.cancel()
            
            // Load the sentence translation
            loadChatGPTBreakdown()
            
            // Prepare audio
            prepareAudio()
        }
        .onDisappear {
            // Clean up when popup disappears
            breakdownTask?.cancel()
            characterTask?.cancel()
            selectedWords.removeAll()
            characterAnalyses.removeAll()
            chatGPTBreakdown = ""
            isLoadingCharacter = false
            isLoadingBreakdown = false
            showAllBreakdowns = false
            isLoadingAllBreakdowns = false
            
            // Audio cleanup handled automatically when view disappears
            isPlaying = false
        }
    }
    
    // MARK: - Helper Methods
    
    private func openInPleco() {
        if let encodedText = chineseText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "plecoapi://x-callback-url/s?q=\(encodedText)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func prepareAudio() {
        guard ttsService.isConfigured() else { return }
        
        Task {
            do {
                // Determine script from the Chinese text
                let script: ChineseScript = .simplified // Default to simplified
                let asset = try await ttsService.generateAudio(for: chineseText, script: script)
                await MainActor.run {
                    self.audioAsset = asset
                }
            } catch {
                // Handle error silently
            }
        }
    }
    
    private func playOrPauseAudio() {
        if isPlaying {
            // Can't pause with current TTSService protocol, just stop
            isPlaying = false
        } else {
            if audioAsset != nil {
                // Play existing audio
                playAudio()
            } else {
                // Generate and play
                generateAndPlayAudio()
            }
        }
    }
    
    private func playAudio() {
        guard let audioAsset = audioAsset else { return }
        
        isPlaying = true
        
        Task {
            do {
                // TTSService doesn't have a play method in current protocol
                // Would need to handle audio playback differently
                // For now, just simulate playback
                await MainActor.run {
                    // Simulate audio playing for 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isPlaying = false
                    }
                }
            } catch {
                await MainActor.run {
                    isPlaying = false
                }
            }
        }
    }
    
    private func generateAndPlayAudio() {
        guard ttsService.isConfigured() else { return }
        
        isGeneratingAudio = true
        
        Task {
            do {
                // Determine script from the Chinese text
                let script: ChineseScript = .simplified // Default to simplified
                let asset = try await ttsService.generateAudio(for: chineseText, script: script)
                self.audioAsset = asset
                
                await MainActor.run {
                    isGeneratingAudio = false
                    // Simulate playing
                    isPlaying = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isPlaying = false
                    }
                }
            } catch {
                await MainActor.run {
                    isGeneratingAudio = false
                    isPlaying = false
                }
            }
        }
    }
    
    private func loadAllCharacterBreakdowns() {
        guard chatGPTService.isConfigured() else { return }
        
        isLoadingAllBreakdowns = true
        showAllBreakdowns = true
        
        // Extract all unique Chinese characters from the text
        let chineseCharacters = chineseText.compactMap { char -> String? in
            let charStr = String(char)
            if let scalar = charStr.unicodeScalars.first {
                let value = scalar.value
                let isChinese = (0x4E00...0x9FFF).contains(value) || 
                              (0x3400...0x4DBF).contains(value) ||
                              (0x20000...0x2A6DF).contains(value) ||
                              (0x2A700...0x2B73F).contains(value) ||
                              (0x2B740...0x2B81F).contains(value) ||
                              (0x2B820...0x2CEAF).contains(value) ||
                              (0xF900...0xFAFF).contains(value) ||
                              (0x2F800...0x2FA1F).contains(value)
                
                return isChinese ? charStr : nil
            }
            return nil
        }
        
        // Load analysis for each character
        Task {
            for (index, char) in chineseCharacters.enumerated() {
                if !selectedWords.contains(where: { $0.contains(char) }) {
                    // Only load if not already analyzed
                    await loadCharacterAnalysisForAll(character: char, at: index)
                }
            }
            
            await MainActor.run {
                isLoadingAllBreakdowns = false
            }
        }
    }
    
    private func loadCharacterAnalysisForAll(character: String, at position: Int) async {
        var fullAnalysis = ""
        var currentWord = character
        var isFirstLine = true
        
        do {
            for try await chunk in chatGPTService.streamCharacterAnalysis(character: character, context: chineseText, position: position) {
                if !Task.isCancelled {
                    fullAnalysis += chunk
                    
                    // Check if we've received the first line (the word)
                    if isFirstLine && fullAnalysis.contains("\n") {
                        let lines = fullAnalysis.split(separator: "\n", maxSplits: 1)
                        if let firstLine = lines.first {
                            currentWord = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // Add to selected words if not already there
                            await MainActor.run {
                                if !selectedWords.contains(currentWord) {
                                    selectedWords.append(currentWord)
                                }
                            }
                            isFirstLine = false
                        }
                    }
                }
            }
            
            // Final update after stream completes
            await MainActor.run {
                let lines = fullAnalysis.split(separator: "\n")
                if lines.count > 1 {
                    let analysis = lines.dropFirst().joined(separator: "\n")
                    if !analysis.isEmpty {
                        characterAnalyses[currentWord] = analysis
                    }
                }
            }
        } catch {
            // Silently skip errors for batch loading
        }
    }
    
    private func loadCharacterAnalysis(for character: String, at position: Int) {
        guard chatGPTService.isConfigured() else { return }
        
        isLoadingCharacter = true
        
        characterTask = Task {
            var isFirstLine = true
            var fullAnalysis = ""
            var currentWord = character // Start with the single character
            
            do {
                for try await chunk in chatGPTService.streamCharacterAnalysis(character: character, context: chineseText, position: position) {
                    if !Task.isCancelled {
                        fullAnalysis += chunk
                        
                        // Check if we've received the first line (the word)
                        if isFirstLine && fullAnalysis.contains("\n") {
                            let lines = fullAnalysis.split(separator: "\n", maxSplits: 1)
                            if let firstLine = lines.first {
                                currentWord = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                // Add to selected words if not already there
                                await MainActor.run {
                                    if !selectedWords.contains(currentWord) {
                                        selectedWords.append(currentWord)
                                    }
                                }
                                isFirstLine = false
                            }
                        }
                        
                        // Update the analysis for this word
                        await MainActor.run {
                            let lines = fullAnalysis.split(separator: "\n")
                            if lines.count > 1 {
                                // Skip first line (word), show rest
                                let analysis = lines.dropFirst().joined(separator: "\n")
                                characterAnalyses[currentWord] = analysis
                            }
                        }
                    }
                }
                
                // Final update after stream completes
                await MainActor.run {
                    let lines = fullAnalysis.split(separator: "\n")
                    if lines.count > 1 {
                        let analysis = lines.dropFirst().joined(separator: "\n")
                        if !analysis.isEmpty {
                            characterAnalyses[currentWord] = analysis
                        }
                    } else if !fullAnalysis.isEmpty && !fullAnalysis.contains("\n") {
                        // If we only got one line back (the word), still show it
                        characterAnalyses[currentWord] = "No additional analysis available"
                    }
                }
            } catch {
                await MainActor.run {
                    characterAnalyses[currentWord] = "Error analyzing"
                }
            }
            
            await MainActor.run {
                isLoadingCharacter = false
            }
        }
    }
    
    private func loadChatGPTBreakdown() {
        guard chatGPTService.isConfigured() else { return }
        
        isLoadingBreakdown = true
        chatGPTBreakdown = ""
        
        breakdownTask = Task {
            do {
                var isFirstChunk = true
                for try await chunk in chatGPTService.streamBreakdown(chineseText: chineseText, isStandalone: true) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            if isFirstChunk {
                                isLoadingBreakdown = false
                                isFirstChunk = false
                            }
                            chatGPTBreakdown += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    chatGPTBreakdown = "Error loading breakdown"
                    isLoadingBreakdown = false
                }
            }
        }
    }
}

// MARK: - Standalone Popup Button Style
private struct StandalonePopupButtonStyle: ButtonStyle {
    var isActive: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? .white : T.C.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? T.C.accent : T.C.ink.opacity(0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}