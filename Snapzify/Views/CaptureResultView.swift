import SwiftUI
import AVFoundation

// Import required components
// Note: TappableCharactersView is in DocumentInteractionView.swift
// AudioAsset is in DataModels.swift
// Button styles and RootBackground are in Theme.swift

struct CaptureResultView: View {
    @Binding var chineseText: String
    let capturedImage: UIImage?
    @Binding var isShowing: Bool
    let homeViewModel: HomeViewModel

    @State private var appendNextCapture = false
    @State private var showCamera = false
    @State private var isProcessing = false

    @State private var chatGPTBreakdown = ""
    @State private var isLoadingBreakdown = false
    @State private var breakdownTask: Task<Void, Never>?
    @State private var selectedWords: [String] = []
    @State private var characterAnalyses: [String: String] = [:]
    @State private var isLoadingCharacter = false
    @State private var characterTask: Task<Void, Never>?
    @State private var isPlaying = false
    @State private var isGeneratingAudio = false
    @State private var audioAsset: AudioAsset?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlayerDelegate: AudioPlayerDelegate?
    @State private var showChatInterface = false
    @State private var chatInput = ""
    @State private var chatResponse = ""
    @State private var chatHistory: [(role: String, content: String)] = []
    @State private var isLoadingChat = false
    @State private var chatTask: Task<Void, Never>?
    @State private var chatScrollProxy: ScrollViewProxy?
    @FocusState private var isChatInputFocused: Bool

    private let chatGPTService = ServiceContainer.shared.chatGPTService
    private let ttsService = ServiceContainer.shared.ttsService
    private let ocrService = ServiceContainer.shared.ocrService

    var body: some View {
        NavigationView {
            RootBackground {
                VStack(spacing: 0) {
                    // Header with Chinese text
                    ScrollView {
                        VStack(spacing: T.S.lg) {
                            // Tappable Chinese text
                            TappableCharactersView(
                                text: chineseText,
                                selectedWords: $selectedWords,
                                onCharacterTap: { char, position in
                                    loadCharacterAnalysis(for: char, at: position)
                                }
                            )
                            .padding(.horizontal)

                            // Translation and breakdown
                            VStack(alignment: .leading, spacing: T.S.md) {
                                if chatGPTBreakdown.isEmpty && isLoadingBreakdown {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Analyzing text...")
                                            .font(.system(size: 14))
                                            .foregroundStyle(T.C.ink2)
                                    }
                                    .padding()
                                } else if !chatGPTBreakdown.isEmpty {
                                    Text(chatGPTBreakdown)
                                        .font(.system(size: 14))
                                        .foregroundStyle(T.C.ink2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(T.C.card)
                                        )
                                }

                                // Character analyses
                                if !selectedWords.isEmpty || isLoadingCharacter {
                                    VStack(alignment: .leading, spacing: T.S.sm) {
                                        ForEach(selectedWords, id: \.self) { word in
                                            if let analysis = characterAnalyses[word] {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("\(word):")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundStyle(T.C.ink)
                                                    Text(analysis)
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(T.C.ink2)
                                                }
                                                .padding()
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(T.C.card)
                                                )
                                            }
                                        }

                                        if isLoadingCharacter {
                                            HStack {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                Text("Analyzing character...")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(T.C.ink2)
                                            }
                                            .padding()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)

                            // Chat interface
                            if showChatInterface {
                                VStack(spacing: T.S.md) {
                                    // Chat history
                                    if !chatHistory.isEmpty {
                                        ScrollViewReader { proxy in
                                            ScrollView {
                                                VStack(alignment: .leading, spacing: T.S.md) {
                                                    ForEach(chatHistory.indices, id: \.self) { index in
                                                        let message = chatHistory[index]
                                                        HStack(alignment: .top, spacing: T.S.sm) {
                                                            Text(message.role == "user" ? "Question:" : "Answer:")
                                                                .font(.system(size: 13, weight: .semibold))
                                                                .foregroundStyle(T.C.ink2)
                                                                .frame(width: 70, alignment: .topLeading)

                                                            Text(message.content)
                                                                .font(.system(size: 14))
                                                                .foregroundStyle(T.C.ink)
                                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                        }
                                                        .id(index)
                                                    }

                                                    if isLoadingChat && chatResponse.isEmpty {
                                                        HStack {
                                                            Text("Answer:")
                                                                .font(.system(size: 13, weight: .semibold))
                                                                .foregroundStyle(T.C.ink2)
                                                                .frame(width: 70, alignment: .topLeading)
                                                            ProgressView()
                                                                .scaleEffect(0.8)
                                                        }
                                                        .id("loading")
                                                    } else if !chatResponse.isEmpty {
                                                        HStack(alignment: .top, spacing: T.S.sm) {
                                                            Text("Answer:")
                                                                .font(.system(size: 13, weight: .semibold))
                                                                .foregroundStyle(T.C.ink2)
                                                                .frame(width: 70, alignment: .topLeading)

                                                            Text(chatResponse)
                                                                .font(.system(size: 14))
                                                                .foregroundStyle(T.C.ink)
                                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                        }
                                                        .id("current")
                                                    }
                                                }
                                                .padding()
                                            }
                                            .frame(maxHeight: 200)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(T.C.card.opacity(0.5))
                                            )
                                            .onAppear {
                                                chatScrollProxy = proxy
                                            }
                                            .onChange(of: chatResponse) { _ in
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    proxy.scrollTo("current", anchor: .bottom)
                                                }
                                            }
                                            .onChange(of: chatHistory.count) { _ in
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    if !chatHistory.isEmpty {
                                                        proxy.scrollTo(chatHistory.count - 1, anchor: .bottom)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Chat input
                                    HStack(spacing: T.S.sm) {
                                        TextField("Ask about this text...", text: $chatInput)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .focused($isChatInputFocused)
                                            .submitLabel(.send)
                                            .onSubmit {
                                                if !chatInput.isEmpty {
                                                    sendChatMessage()
                                                }
                                            }

                                        Button {
                                            sendChatMessage()
                                        } label: {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(chatInput.isEmpty || isLoadingChat ? T.C.ink2 : T.C.accent)
                                        }
                                        .disabled(chatInput.isEmpty || isLoadingChat)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, T.S.md)
                            }

                            // Action buttons
                            HStack(spacing: T.S.md) {
                                // Audio button
                                if isGeneratingAudio {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: T.C.accent))
                                            .scaleEffect(0.6)
                                        Text("Loading...")
                                            .font(.caption)
                                            .foregroundStyle(T.C.ink2)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(T.C.card)
                                    )
                                } else if isPlaying {
                                    Button {
                                        playOrPauseAudio()
                                    } label: {
                                        Label("Pause", systemImage: "pause.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                } else {
                                    Button {
                                        playOrPauseAudio()
                                    } label: {
                                        Label("Play", systemImage: "play.fill")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                }

                                // Pleco button
                                Button {
                                    openInPleco()
                                } label: {
                                    Label("Pleco", systemImage: "book")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryButtonStyle())

                                // Ask button
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showChatInterface.toggle()
                                        if showChatInterface {
                                            isChatInputFocused = true
                                        }
                                    }
                                } label: {
                                    Label(showChatInterface ? "Hide" : "Ask", systemImage: "questionmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                            .padding(.horizontal)

                            // Capture button row with append checkbox
                            HStack(spacing: T.S.md) {
                                Button {
                                    showCamera = true
                                } label: {
                                    Label(isProcessing ? "Processing..." : "Capture", systemImage: "camera")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(isProcessing)

                                Toggle(isOn: $appendNextCapture) {
                                    Text("Append")
                                        .font(.system(size: 14))
                                        .foregroundStyle(T.C.ink2)
                                }
                                .toggleStyle(CheckboxToggleStyle())
                                .frame(width: 100)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Capture Result")
                        .font(.headline)
                        .foregroundStyle(T.C.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowing = false
                    }
                    .foregroundStyle(T.C.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCamera) {
            CustomCameraView { image in
                showCamera = false
                isProcessing = true

                // Update append mode in view model
                homeViewModel.appendMode = appendNextCapture

                Task {
                    await homeViewModel.processCapturedImage(image, fromCaptureResult: true)

                    await MainActor.run {
                        isProcessing = false
                        // The text binding will automatically update
                        chineseText = homeViewModel.capturedText
                    }
                }
            } onCancel: {
                showCamera = false
            }
        }
        .onAppear {
            loadChatGPTBreakdown()
            prepareAudio()
        }
        .onChange(of: chineseText) { _ in
            // Reload breakdown when text changes (after append)
            loadChatGPTBreakdown()
            prepareAudio()
        }
        .onDisappear {
            breakdownTask?.cancel()
            characterTask?.cancel()
            chatTask?.cancel()
            audioPlayer?.stop()
            audioPlayer = nil
        }
    }

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
                let script: ChineseScript = .simplified
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
            audioPlayer?.stop()
            isPlaying = false
        } else {
            if audioAsset != nil {
                playAudio()
            } else {
                generateAndPlayAudio()
            }
        }
    }

    private func playAudio() {
        guard let audioAsset = audioAsset else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: audioAsset.fileURL)
            audioPlayer?.volume = 1.0

            audioPlayerDelegate = AudioPlayerDelegate {
                DispatchQueue.main.async { [self] in
                    self.isPlaying = false
                    self.audioPlayer = nil
                    self.audioPlayerDelegate = nil
                }
            }
            audioPlayer?.delegate = audioPlayerDelegate

            audioPlayer?.prepareToPlay()
            if audioPlayer?.play() == true {
                isPlaying = true
            }
        } catch {
            print("Failed to play audio: \(error)")
            isPlaying = false
        }
    }

    private func generateAndPlayAudio() {
        guard ttsService.isConfigured() else { return }

        isGeneratingAudio = true

        Task {
            do {
                let script: ChineseScript = .simplified
                let asset = try await ttsService.generateAudio(for: chineseText, script: script)

                await MainActor.run {
                    self.audioAsset = asset
                    isGeneratingAudio = false

                    do {
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.setCategory(.playback, mode: .default, options: [])
                        try audioSession.setActive(true)

                        self.audioPlayer = try AVAudioPlayer(contentsOf: asset.fileURL)
                        self.audioPlayer?.volume = 1.0

                        self.audioPlayerDelegate = AudioPlayerDelegate {
                            DispatchQueue.main.async { [self] in
                                self.isPlaying = false
                                self.audioPlayer = nil
                                self.audioPlayerDelegate = nil
                            }
                        }
                        self.audioPlayer?.delegate = self.audioPlayerDelegate

                        self.audioPlayer?.prepareToPlay()
                        if self.audioPlayer?.play() == true {
                            self.isPlaying = true
                        }
                    } catch {
                        print("Failed to play audio: \(error)")
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

    private func loadCharacterAnalysis(for character: String, at position: Int) {
        guard chatGPTService.isConfigured() else { return }

        isLoadingCharacter = true

        characterTask = Task {
            var fullAnalysis = ""
            var currentWord = character

            do {
                for try await chunk in chatGPTService.streamCharacterAnalysis(
                    character: character,
                    context: chineseText,
                    position: position
                ) {
                    if !Task.isCancelled {
                        fullAnalysis += chunk

                        await MainActor.run {
                            let lines = fullAnalysis.split(separator: "\n")
                            if let firstLine = lines.first {
                                currentWord = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !selectedWords.contains(currentWord) {
                                    selectedWords.append(currentWord)
                                }
                            }

                            if lines.count > 1 {
                                let analysis = lines.dropFirst().joined(separator: "\n")
                                characterAnalyses[currentWord] = analysis
                            }
                        }
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
                // Stream the breakdown with standalone mode for complete analysis
                for try await chunk in chatGPTService.streamBreakdown(
                    chineseText: chineseText,
                    isStandalone: true
                ) {
                    if !Task.isCancelled {
                        await MainActor.run {
                            chatGPTBreakdown += chunk
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    chatGPTBreakdown = "Error loading analysis"
                    isLoadingBreakdown = false
                }
            }

            await MainActor.run {
                isLoadingBreakdown = false
            }
        }
    }

    private func sendChatMessage() {
        guard !chatInput.isEmpty else { return }
        guard chatGPTService.isConfigured() else { return }

        let userMessage = chatInput
        chatHistory.append((role: "user", content: userMessage))
        chatInput = ""
        chatResponse = ""
        isLoadingChat = true

        chatTask = Task {
            do {
                // Build context for the conversation
                var conversationContext = "Previous conversation:\n"
                for message in chatHistory.dropLast() {  // Exclude the message we just added
                    conversationContext += "\(message.role == "user" ? "User" : "Assistant"): \(message.content)\n"
                }

                let fullPrompt = """
                You are helping a Chinese language learner understand this text: \(chineseText)

                \(conversationContext)

                User: \(userMessage)

                Please provide a helpful response. IMPORTANT: If your response contains any Chinese text, you MUST include:
                1. The Chinese text
                2. The English translation
                3. The pinyin

                Format each Chinese phrase/sentence like this (but without labels):
                中文文本
                English translation
                pinyin
                """

                var fullResponse = ""
                for try await chunk in chatGPTService.streamCustomPrompt(chineseText: chineseText, userPrompt: fullPrompt) {
                    if !Task.isCancelled {
                        fullResponse += chunk
                        await MainActor.run {
                            chatResponse = fullResponse
                        }
                    }
                }

                await MainActor.run {
                    chatHistory.append((role: "assistant", content: fullResponse))
                    chatResponse = ""
                    isLoadingChat = false
                }
            } catch {
                await MainActor.run {
                    chatResponse = "Error: Unable to get response"
                    isLoadingChat = false
                }
            }
        }
    }
}

// Audio Player Delegate
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// Custom checkbox toggle style
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundStyle(configuration.isOn ? T.C.accent : T.C.ink2)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}