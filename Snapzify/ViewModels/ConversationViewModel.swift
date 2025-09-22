import Foundation
import SwiftUI
import AVFoundation
import Speech

struct ConversationMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
    var chineseSegments: [ChineseTextSegment] = []
}

struct ChineseTextSegment: Identifiable {
    let id = UUID()
    let text: String
    let range: Range<String.Index>
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
    @Published var showInfo = false
    
    // Services
    private let translationService: EnglishToChineseTranslationService
    private let ttsService: TTSService
    private var conversationTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    // Voice recording
    @Published var isRecording = false
    private var audioRecorder: AVAudioRecorder?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Chinese text popup
    @Published var selectedChineseText: String? = nil
    @Published var showChinesePopup = false
    
    init() {
        self.translationService = EnglishToChineseTranslationServiceImpl(
            configService: ServiceContainer.shared.configService
        )
        self.ttsService = TTSServiceOpenAI(
            configService: ServiceContainer.shared.configService
        )
        setupAudioSession()
        requestSpeechAuthorization()
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

    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("Speech recognition authorized")
                case .denied, .restricted, .notDetermined:
                    print("Speech recognition not authorized")
                @unknown default:
                    break
                }
            }
        }
    }
    
    var canStartConversation: Bool {
        !scenario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func startConversation() {
        guard canStartConversation else { return }
        
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
                await playTTS(for: greeting)
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
        
        // Add user message
        let message = ConversationMessage(
            content: userMessage,
            isUser: true
        )
        messages.append(message)
        
        // Process AI response
        Task {
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
                await playTTS(for: aiResponse)
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
        conversationTask?.cancel()
        isConversationActive = false
        isProcessing = false
        
        // Reset for next conversation
        scenario = ""
        userInput = ""
        messages = []
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

            // Play the audio
            audioPlayer = try AVAudioPlayer(contentsOf: audioAsset.fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to generate or play TTS: \(error)")
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
                    segments.append(ChineseTextSegment(text: chineseText, range: range))
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

    // MARK: - Voice Recording

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard speechRecognizer?.isAvailable ?? false else {
            print("Speech recognizer not available")
            return
        }

        do {
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            let inputNode = audioEngine.inputNode

            guard let recognitionRequest = recognitionRequest else {
                print("Unable to create recognition request")
                return
            }

            recognitionRequest.shouldReportPartialResults = true

            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    self.userInput = result.bestTranscription.formattedString
                }

                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecording()
                }
            }

            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    deinit {
        conversationTask?.cancel()
        audioEngine.stop()
        audioPlayer?.stop()
    }
}