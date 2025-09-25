import SwiftUI
import AVFoundation

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
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlayerDelegate: AudioPlayerDelegate?
    @State private var showChatInterface = false
    @State private var chatInput = ""
    @State private var chatResponse = ""
    @State private var isLoadingChatResponse = false
    @State private var chatTask: Task<Void, Never>?
    @State private var chatHistory: [(role: String, content: String)] = []
    @FocusState private var isChatInputFocused: Bool
    
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

            // Spacing after Audio
            Spacer().frame(width: T.S.sm)

            // ChatGPT button (with question mark icon like home page)
            Button {
                showChatInterface.toggle()
                if showChatInterface {
                    isChatInputFocused = true
                }
            } label: {
                Image(systemName: showChatInterface ? "xmark.circle.fill" : "questionmark.circle")
                    .font(.system(size: 16))
            }
            .buttonStyle(StandalonePopupButtonStyle(isActive: showChatInterface))
            
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
            ScrollViewReader { mainScrollProxy in
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

                    // ChatGPT Interface
                    if showChatInterface {
                        Divider()
                            .padding(.vertical, 4)
                            .id("chatInterface")

                        VStack(alignment: .leading, spacing: T.S.sm) {
                            // Chat input
                            HStack {
                                TextField("Ask about this text...", text: $chatInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .focused($isChatInputFocused)
                                    .onSubmit {
                                        sendChatMessage()
                                    }

                                Button {
                                    sendChatMessage()
                                } label: {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 14))
                                }
                                .disabled(chatInput.isEmpty || isLoadingChatResponse)
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(chatInput.isEmpty || isLoadingChatResponse ? .gray : T.C.accent)
                            }

                            // Chat response area (no nested scroll)
                            VStack(alignment: .leading, spacing: 8) {
                                if !chatResponse.isEmpty {
                                    Text(chatResponse)
                                        .font(.system(size: 13))
                                        .foregroundStyle(T.C.ink2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.1))
                                        )
                                }

                                if isLoadingChatResponse {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Thinking...")
                                            .font(.system(size: 13))
                                            .foregroundStyle(T.C.ink2)
                                    }
                                    .padding(.horizontal, 4)
                                }

                                // Anchor for scrolling to bottom of response
                                Color.clear
                                    .frame(height: 1)
                                    .id("chatResponseBottom")
                            }
                        }
                    }
                }
                .padding(.horizontal, T.S.lg)
                .padding(.vertical, T.S.sm)
                    .onChange(of: isLoadingChatResponse) { loading in
                        if loading {
                            // Small delay to ensure UI updates
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    mainScrollProxy.scrollTo("chatResponseBottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onChange(of: chatResponse) { _ in
                        // Keep scrolling to bottom as response streams in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mainScrollProxy.scrollTo("chatResponseBottom", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollIndicators(.visible, axes: .vertical)
            }
            
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
            chatTask?.cancel()
            showChatInterface = false
            chatInput = ""
            chatResponse = ""
            chatHistory = []
            isLoadingChatResponse = false
            
            // Load the sentence translation
            loadChatGPTBreakdown()
            
            // Prepare audio
            prepareAudio()
        }
        .onDisappear {
            // Clean up when popup disappears
            breakdownTask?.cancel()
            characterTask?.cancel()
            chatTask?.cancel()
            selectedWords.removeAll()
            characterAnalyses.removeAll()
            chatGPTBreakdown = ""
            isLoadingCharacter = false
            isLoadingBreakdown = false
            showAllBreakdowns = false
            isLoadingAllBreakdowns = false
            showChatInterface = false
            chatInput = ""
            chatResponse = ""
            isLoadingChatResponse = false
            
            // Audio cleanup
            audioPlayer?.stop()
            audioPlayer = nil
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

    private func sendChatMessage() {
        guard !chatInput.isEmpty, chatGPTService.isConfigured() else { return }

        let userQuestion = chatInput
        chatInput = ""
        isLoadingChatResponse = true
        chatResponse = ""

        // Add user question to history
        chatHistory.append((role: "user", content: userQuestion))

        // Build context for the chat
        var contextPrompt = "Context: The user is studying this Chinese text: \"\(chineseText)\""

        if !chatGPTBreakdown.isEmpty {
            contextPrompt += "\n\nTranslation: \(chatGPTBreakdown)"
        }

        if !characterAnalyses.isEmpty {
            contextPrompt += "\n\nCharacter breakdowns:"
            for (word, analysis) in characterAnalyses {
                contextPrompt += "\n\(word): \(analysis)"
            }
        }

        // Add conversation history for context
        if chatHistory.count > 1 {
            contextPrompt += "\n\nConversation history:"
            for (index, message) in chatHistory.enumerated() {
                if index < chatHistory.count - 1 {  // Don't duplicate the current question
                    contextPrompt += "\n\(message.role == "user" ? "User" : "Assistant"): \(message.content)"
                }
            }
        }

        contextPrompt += "\n\nCurrent user question: \(userQuestion)"
        contextPrompt += """

        Please answer the user's question about this Chinese text, considering the conversation history.

        IMPORTANT: Structure your response as follows:
        1. First, provide your answer in Chinese (if the question is about Chinese language)
        2. Then add one line break
        3. Then provide the English translation of your Chinese response (no brackets or prefix, just the translation)
        4. Then add one line break
        5. Then provide the pinyin transcription of YOUR CHINESE RESPONSE ONLY (not the original text, but the Chinese answer you just gave)

        Be concise and helpful. If your response doesn't include Chinese, just answer normally without the translation/pinyin.
        """

        chatTask = Task {
            do {
                var fullResponse = ""
                for try await chunk in chatGPTService.streamCustomPrompt(chineseText: "", userPrompt: contextPrompt) {
                    if !Task.isCancelled {
                        fullResponse += chunk
                        await MainActor.run {
                            isLoadingChatResponse = false
                            chatResponse = fullResponse
                        }
                    }
                }

                // Add assistant response to history
                await MainActor.run {
                    chatHistory.append((role: "assistant", content: fullResponse))
                }
            } catch {
                await MainActor.run {
                    chatResponse = "Error: Unable to get response"
                    isLoadingChatResponse = false
                }
            }
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
            // Stop playing
            audioPlayer?.stop()
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

        do {
            // Configure audio session for playback
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)

            // Create audio player
            audioPlayer = try AVAudioPlayer(contentsOf: audioAsset.fileURL)
            audioPlayer?.volume = 1.0

            // Create and set delegate
            audioPlayerDelegate = AudioPlayerDelegate {
                DispatchQueue.main.async { [self] in
                    self.isPlaying = false
                    self.audioPlayer = nil
                    self.audioPlayerDelegate = nil
                }
            }
            audioPlayer?.delegate = audioPlayerDelegate

            // Prepare and play
            audioPlayer?.prepareToPlay()
            if audioPlayer?.play() == true {
                isPlaying = true
            } else {
                print("Failed to start audio playback")
                isPlaying = false
                audioPlayer = nil
                audioPlayerDelegate = nil
            }
        } catch {
            print("Failed to create audio player: \(error)")
            isPlaying = false
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

                await MainActor.run {
                    self.audioAsset = asset
                    isGeneratingAudio = false

                    // Play the audio
                    do {
                        // Configure audio session for playback
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.setCategory(.playback, mode: .default, options: [])
                        try audioSession.setActive(true)

                        self.audioPlayer = try AVAudioPlayer(contentsOf: asset.fileURL)
                        self.audioPlayer?.volume = 1.0

                        // Create and set delegate
                        self.audioPlayerDelegate = AudioPlayerDelegate {
                            DispatchQueue.main.async { [self] in
                                self.isPlaying = false
                                self.audioPlayer = nil
                                self.audioPlayerDelegate = nil
                            }
                        }
                        self.audioPlayer?.delegate = self.audioPlayerDelegate

                        // Prepare and play
                        self.audioPlayer?.prepareToPlay()
                        if self.audioPlayer?.play() == true {
                            self.isPlaying = true
                        } else {
                            print("Failed to start audio playback")
                            self.isPlaying = false
                            self.audioPlayer = nil
                            self.audioPlayerDelegate = nil
                        }
                    } catch {
                        print("Failed to create audio player: \(error)")
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
// MARK: - Audio Player Delegate
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// MARK: - Button Style
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