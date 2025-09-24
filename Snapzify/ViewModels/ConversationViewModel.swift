import Foundation
import SwiftUI
import AVFoundation

struct ConversationMessage: Identifiable, Codable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
    var chineseSegments: [ChineseTextSegment] = []
    var isNatural: Bool? = nil
    var suggestions: String? = nil
}

struct ChineseTextSegment: Identifiable, Codable {
    let id = UUID()
    let text: String
    let rangeStart: Int
    let rangeEnd: Int

    init(text: String, range: Range<String.Index>, in fullText: String) {
        self.text = text
        self.rangeStart = fullText.distance(from: fullText.startIndex, to: range.lowerBound)
        self.rangeEnd = fullText.distance(from: fullText.startIndex, to: range.upperBound)
    }
}

struct SessionData: Codable {
    let scenario: String
    let messages: [ConversationMessage]
    let timestamp: Date
}

@MainActor
class ConversationViewModel: ObservableObject {
    // Setup fields
    @Published var scenario: String = ""

    // Conversation state
    @Published var isConversationActive = false
    @Published var messages: [ConversationMessage] = []
    @Published var userInput: String = ""
    @Published var isProcessing = false
    @Published var isGeneratingAudio = false
    @Published var showInfo = false
    @Published var hasPreviousSession = false
    
    // Services
    private let translationService: EnglishToChineseTranslationService
    private let ttsService: TTSService
    private let configService: ConfigService
    private var conversationTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    // Voice recording
    @Published var isRecording = false
    private var audioRecorder: AVAudioRecorder?
    private let audioSession = AVAudioSession.sharedInstance()
    private var recordingURL: URL?
    private var recordingTask: Task<Void, Never>?

    // Chinese text popup
    @Published var selectedChineseText: String? = nil
    @Published var showChinesePopup = false
    
    init() {
        self.configService = ServiceContainer.shared.configService
        self.translationService = EnglishToChineseTranslationServiceImpl(
            configService: ServiceContainer.shared.configService
        )
        self.ttsService = TTSServiceOpenAI(
            configService: ServiceContainer.shared.configService
        )
        // Don't setup audio session here - defer until needed

        // Check if there's a previous session
        loadPreviousSessionIfExists()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    
    var canStartConversation: Bool {
        !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func startConversation() {
        guard canStartConversation else { return }

        // Setup audio session when conversation starts
        setupAudioSession()

        isConversationActive = true
        messages = []

        // Generate initial AI greeting based on scenario
        Task {
            await generateInitialGreeting()
        }
    }
    
    private func generateInitialGreeting() async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            var greeting = ""
            
            // Stream the initial greeting
            for try await chunk in translationService.streamConversation(
                scenario: scenario,
                messages: [],
                userMessage: "[START]"
            ) {
                greeting += chunk
            }
            
            // Add AI greeting with Chinese segments detected
            if !greeting.isEmpty {
                let segments = detectChineseSegments(in: greeting)
                var message = ConversationMessage(
                    content: greeting,
                    isUser: false
                )
                message.chineseSegments = segments
                messages.append(message)

                // Play TTS for AI response
                await MainActor.run {
                    self.isGeneratingAudio = true
                }
                await playTTS(for: greeting)
                await MainActor.run {
                    self.isGeneratingAudio = false
                }
            }
        } catch {
            print("Error generating initial greeting: \(error)")
            // Add error message
            let errorMessage = ConversationMessage(
                content: "Sorry, I couldn't start the conversation. Please try again.",
                isUser: false
            )
            messages.append(errorMessage)
        }
    }
    
    func sendMessage() {
        guard !userInput.isEmpty, !isProcessing else { return }

        let userMessage = userInput
        userInput = ""

        // Add user message with Chinese segments detected
        let segments = detectChineseSegments(in: userMessage)
        var message = ConversationMessage(
            content: userMessage,
            isUser: true
        )
        message.chineseSegments = segments
        let messageIndex = messages.count
        messages.append(message)

        // Check naturalness and process response
        Task {
            // If message contains Chinese, check naturalness first
            if !segments.isEmpty {
                await checkMessageNaturalness(at: messageIndex)

                // Wait for the naturalness check to complete and check the result
                let shouldProceed = await MainActor.run {
                    // Get the actual updated message
                    guard messageIndex < self.messages.count else { return true }

                    // Check if naturalness has been determined
                    if let isNatural = self.messages[messageIndex].isNatural {
                        if !isNatural {
                            // Message is unnatural, don't send to AI
                            print("Message deemed unnatural, not sending to AI")
                            return false
                        }
                    }
                    return true
                }

                // Exit early if message is unnatural
                if !shouldProceed {
                    return
                }
            }

            // Process AI response (if message is natural or doesn't contain Chinese)
            await processAIResponse(userMessage: userMessage)
        }
    }
    
    private func processAIResponse(userMessage: String) async {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            var aiResponse = ""
            
            // Stream the conversation response
            for try await chunk in translationService.streamConversation(
                scenario: scenario,
                messages: messages.map { ($0.isUser ? "User" : "AI", $0.content) },
                userMessage: userMessage
            ) {
                aiResponse += chunk
            }
            
            // Add AI response with Chinese segments detected
            if !aiResponse.isEmpty {
                let segments = detectChineseSegments(in: aiResponse)
                var message = ConversationMessage(
                    content: aiResponse,
                    isUser: false
                )
                message.chineseSegments = segments
                messages.append(message)

                // Play TTS for AI response
                await MainActor.run {
                    self.isGeneratingAudio = true
                }
                await playTTS(for: aiResponse)
                await MainActor.run {
                    self.isGeneratingAudio = false
                }
            }
        } catch {
            print("Error processing AI response: \(error)")
            // Add error message
            let errorMessage = ConversationMessage(
                content: "Sorry, I encountered an error. Please try again.",
                isUser: false
            )
            messages.append(errorMessage)
        }
    }
    
    func endConversation() {
        // Save current session before ending
        if !messages.isEmpty {
            saveSession()
        }

        conversationTask?.cancel()
        isConversationActive = false
        isProcessing = false

        // Reset for next conversation
        scenario = ""
        userInput = ""
        messages = []
    }

    // MARK: - Session Persistence

    func saveCurrentSession() {
        if !messages.isEmpty {
            saveSession()
        }
    }

    private func saveSession() {
        let sessionData = SessionData(
            scenario: scenario,
            messages: messages,
            timestamp: Date()
        )

        if let encoded = try? JSONEncoder().encode(sessionData) {
            UserDefaults.standard.set(encoded, forKey: "lastConversationSession")
            hasPreviousSession = true
        }
    }

    private func loadPreviousSessionIfExists() {
        if let data = UserDefaults.standard.data(forKey: "lastConversationSession"),
           let session = try? JSONDecoder().decode(SessionData.self, from: data) {
            hasPreviousSession = true
        } else {
            hasPreviousSession = false
        }
    }

    func resumePreviousSession() {
        guard let data = UserDefaults.standard.data(forKey: "lastConversationSession"),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else {
            return
        }

        // Restore the session
        scenario = session.scenario
        messages = session.messages
        isConversationActive = true

        // Setup audio session when resuming
        setupAudioSession()
    }
    
    // MARK: - TTS Functions

    private func playTTS(for text: String) async {
        guard ttsService.isConfigured() else {
            print("TTS service not configured")
            return
        }

        do {
            // For mixed English/Chinese, we'll use simplified Chinese voice
            let audioAsset = try await ttsService.generateAudio(for: text, script: .simplified)

            // Play the audio on main thread
            await MainActor.run {
                do {
                    // Stop any existing audio
                    self.audioPlayer?.stop()

                    // Configure audio session for playback
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playback, mode: .default, options: [])
                    try audioSession.setActive(true)

                    // Create new player
                    self.audioPlayer = try AVAudioPlayer(contentsOf: audioAsset.fileURL)
                    self.audioPlayer?.volume = 1.0
                    self.audioPlayer?.prepareToPlay()
                    self.audioPlayer?.play()
                } catch {
                    print("Failed to play TTS audio: \(error)")
                }
            }
        } catch {
            print("Failed to generate TTS: \(error)")
        }
    }

    // MARK: - Chinese Text Detection

    private func detectChineseSegments(in text: String) -> [ChineseTextSegment] {
        var segments: [ChineseTextSegment] = []
        let pattern = "[\u{4E00}-\u{9FFF}\u{3400}-\u{4DBF}\u{20000}-\u{2A6DF}\u{2A700}-\u{2B73F}\u{2B740}-\u{2B81F}\u{2B820}-\u{2CEAF}\u{2CEB0}-\u{2EBEF}]+"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

            for match in matches {
                if let range = Range(match.range, in: text) {
                    let chineseText = String(text[range])
                    segments.append(ChineseTextSegment(text: chineseText, range: range, in: text))
                }
            }
        } catch {
            print("Error detecting Chinese segments: \(error)")
        }

        return segments
    }

    func selectChineseText(_ text: String) {
        selectedChineseText = text
        showChinesePopup = true
    }

    func forceSendMessage(at index: Int) {
        guard index < messages.count, messages[index].isUser else { return }

        let userMessage = messages[index].content

        // Process AI response regardless of naturalness
        Task {
            await processAIResponse(userMessage: userMessage)
        }
    }

    private func checkMessageNaturalness(at index: Int) async {
        guard index < messages.count, messages[index].isUser else { return }

        // Build conversation context for better suggestions
        var conversationContext = "Scenario: \(scenario)\n\n"

        // Include recent conversation history (last 5 exchanges)
        let recentMessages = messages.prefix(index).suffix(10)
        for msg in recentMessages {
            conversationContext += "\(msg.isUser ? "User" : "AI"): \(msg.content)\n"
        }

        do {
            let result = try await translationService.checkNaturalness(
                messages[index].content,
                conversationContext: conversationContext
            )
            await MainActor.run {
                messages[index].isNatural = result.isNatural
                messages[index].suggestions = result.suggestions
            }
        } catch {
            print("Failed to check naturalness: \(error)")
            // On error, allow the message to proceed
            await MainActor.run {
                messages[index].isNatural = true
            }
        }
    }

    // MARK: - Voice Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func cancelRecording() {
        guard isRecording else { return }

        // Stop recording
        audioRecorder?.stop()
        isRecording = false

        // Delete the recording file if it exists
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            print("Recording cancelled and file deleted")
        }

        // Clear recording state
        recordingURL = nil
        recordingTask?.cancel()
        recordingTask = nil
    }

    private func startRecording() {
        // Setup audio session if not already done
        setupAudioSession()

        // Request microphone permission
        requestMicrophonePermission { [weak self] granted in
            if granted {
                Task { @MainActor in
                    self?.beginRecording()
                }
            }
        }
    }

    private func beginRecording() {
        do {
            // Configure audio session
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            // Create recording URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            recordingURL = documentsPath.appendingPathComponent("conversation_recording_\(Date().timeIntervalSince1970).m4a")

            guard let recordingURL = recordingURL else { return }

            // Configure recorder settings
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            // Create and start recorder
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecording = true

            print("Started recording at: \(recordingURL)")
        } catch {
            print("Failed to start recording: \(error)")
            isRecording = false
        }
    }

    private func stopRecording() {
        guard isRecording else { return }

        audioRecorder?.stop()
        isRecording = false

        if let url = recordingURL {
            print("Stopped recording, file at: \(url)")
            recordingTask = Task {
                await processRecording(url: url)
            }
        }
    }

    private func processRecording(url: URL) async {
        do {
            // Transcribe the audio using Whisper API for Chinese
            let transcription = try await transcribeAudio(url: url)
            print("Transcription: \(transcription)")

            await MainActor.run {
                // Set the transcribed text as user input and send it
                self.userInput = transcription
                self.sendMessage()
            }

            // Clean up the recording file
            try? FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to process recording: \(error)")
            // Clean up the recording file
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func transcribeAudio(url: URL) async throws -> String {
        guard let key = configService.openAIKey,
              !key.isEmpty else {
            throw TTSError.notConfigured
        }

        let whisperURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: whisperURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add language parameter (Chinese)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("zh\r\n".data(using: .utf8)!)

        // Add audio file
        let audioData = try Data(contentsOf: url)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)

        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TTSError.requestFailed
        }

        let json = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return json.text
    }

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        audioSession.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    deinit {
        conversationTask?.cancel()
        recordingTask?.cancel()
        audioRecorder?.stop()
        audioPlayer?.stop()
    }
}

// MARK: - Transcription Response
private struct TranscriptionResponse: Codable {
    let text: String
}