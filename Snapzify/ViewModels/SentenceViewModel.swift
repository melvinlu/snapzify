import Foundation
import SwiftUI
import AVFoundation
import UIKit

@MainActor
class SentenceViewModel: ObservableObject {
    @Published var sentence: Sentence
    @Published var isExpanded = false
    @Published var isPlaying = false
    @Published var isTranslating = false
    @Published var isGeneratingAudio = false
    @Published var isPreparingAudio = false
    
    let script: ChineseScript
    private let translationService: TranslationService
    private let ttsService: TTSService
    private let autoTranslate: Bool
    private let autoGenerateAudio: Bool
    private let onToggleExpanded: (UUID, Bool) -> Void
    private let onAudioStateChange: ((UUID, Bool) -> Void)?
    private let onUpdate: (Sentence) -> Void
    
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegate?
    
    init(
        sentence: Sentence,
        script: ChineseScript,
        translationService: TranslationService,
        ttsService: TTSService,
        autoTranslate: Bool,
        autoGenerateAudio: Bool,
        isExpanded: Bool = false,
        onToggleExpanded: @escaping (UUID, Bool) -> Void,
        onAudioStateChange: ((UUID, Bool) -> Void)? = nil,
        onUpdate: @escaping (Sentence) -> Void
    ) {
        self.sentence = sentence
        self.script = script
        self.translationService = translationService
        self.ttsService = ttsService
        self.autoTranslate = autoTranslate
        self.autoGenerateAudio = autoGenerateAudio
        self.isExpanded = isExpanded
        self.onToggleExpanded = onToggleExpanded
        self.onAudioStateChange = onAudioStateChange
        self.onUpdate = onUpdate
    }
    
    deinit {
        print("AudioPlayback: SentenceViewModel deinit")
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerDelegate = nil
    }
    
    func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
            onToggleExpanded(sentence.id, isExpanded)
            
            if isExpanded {
                Task {
                    // Don't translate if we're still generating
                    if autoTranslate && sentence.english == nil && sentence.english != "Generating..." {
                        await translateIfNeeded()
                    }
                    
                    // Remove auto audio generation - it will be done on-demand when play is clicked
                }
            }
        }
    }
    
    func translateIfNeeded() async {
        print("🔍 translateIfNeeded called for text: '\(sentence.text)'")
        print("🔍 Current english: \(sentence.english ?? "nil")")
        print("🔍 Current pinyin: \(sentence.pinyin)")
        print("🔍 Current script: \(script)")
        
        // Need translation if either English or pinyin is missing
        guard (sentence.english == nil || sentence.english == "Generating..." || sentence.pinyin.isEmpty),
              translationService.isConfigured() else { 
            print("🔍 Skipping translation - both english and pinyin exist, or service not configured")
            return 
        }
        
        isTranslating = true
        defer { isTranslating = false }
        
        // Use streaming service to get both English and pinyin
        let streamingService = ServiceContainer.shared.streamingChineseProcessingService
        print("🔍 Using streaming service for translation")
        
        do {
            var processedResult: StreamingProcessedSentence?
            
            print("🔍 Calling processStreamingBatch with text: '\(sentence.text)'")
            try await streamingService.processStreamingBatch(
                [sentence.text],
                script: script
            ) { processed in
                print("🔍 Received processed result:")
                print("🔍   - Index: \(processed.index)")
                print("🔍   - Chinese: '\(processed.chinese)'")
                print("🔍   - English: '\(processed.english)'")
                print("🔍   - Pinyin: \(processed.pinyin)")
                processedResult = processed
            }
            
            if let result = processedResult {
                print("🔍 Updating sentence with result:")
                print("🔍   - English: '\(result.english)'")
                print("🔍   - Pinyin count: \(result.pinyin.count)")
                print("🔍   - Pinyin: \(result.pinyin)")
                
                sentence.english = result.english
                sentence.pinyin = result.pinyin
                sentence.status = .translated
                
                print("🔍 After update:")
                print("🔍   - sentence.english: '\(sentence.english ?? "nil")'")
                print("🔍   - sentence.pinyin: \(sentence.pinyin)")
                
                onUpdate(sentence)
                
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                print("🔍 No result received from streaming service")
            }
        } catch {
            print("🔍 Translation failed: \(error)")
            sentence.status = .error("Translation failed")
            onUpdate(sentence)
        }
    }
    
    func generateAudioIfNeeded() async {
        print("AudioGeneration: generateAudioIfNeeded called")
        print("AudioGeneration: Current audioAsset: \(sentence.audioAsset != nil ? "exists" : "nil")")
        print("AudioGeneration: TTS configured: \(ttsService.isConfigured())")
        
        guard sentence.audioAsset == nil,
              ttsService.isConfigured(),
              sentence.english != "Generating..." else { 
            print("AudioGeneration: Skipping generation - audioAsset exists, TTS not configured, or still generating translation")
            return 
        }
        
        print("AudioGeneration: Starting audio generation for text: '\(sentence.text.prefix(50))...'")
        
        await MainActor.run {
            isGeneratingAudio = true
        }
        
        do {
            print("AudioGeneration: Calling TTS service...")
            let audioAsset = try await ttsService.generateAudio(for: sentence.text, script: script)
            print("AudioGeneration: TTS service returned asset with URL: \(audioAsset.fileURL)")
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioAsset.fileURL.path)[.size] as? Int) ?? 0
            print("AudioGeneration: Audio file size: \(fileSize) bytes")
            
            await MainActor.run {
                sentence.audioAsset = audioAsset
                onUpdate(sentence)
                isGeneratingAudio = false  // Set to false here, not in defer
                print("AudioGeneration: Audio asset saved to sentence, isGeneratingAudio set to false")
            }
        } catch {
            print("AudioGeneration: Audio generation failed with error: \(error)")
            print("AudioGeneration: Error details: \(error.localizedDescription)")
            if let ttsError = error as? TTSError {
                print("AudioGeneration: TTS specific error: \(ttsError)")
            }
            
            await MainActor.run {
                isGeneratingAudio = false  // Also set to false on error
                print("AudioGeneration: Error occurred, isGeneratingAudio set to false")
            }
        }
    }
    
    func openInPleco() {
        if let url = URL(string: "plecoapi://x-callback-url/s?q=\(sentence.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }
    
    func playOrPauseAudio() {
        print("AudioPlayback: playOrPauseAudio called, currently isPlaying: \(isPlaying)")
        if isPlaying {
            pauseAudio()
        } else {
            playAudio()
        }
    }
    
    private func playAudio() {
        print("AudioPlayback: playAudio called for sentence: \(sentence.id)")
        print("AudioPlayback: Current isPlaying state: \(isPlaying)")
        print("AudioPlayback: Current audioPlayer exists: \(audioPlayer != nil)")
        
        // Notify that we're about to start playing
        onAudioStateChange?(sentence.id, true)
        
        // Set preparing flag to prevent UI flicker
        isPreparingAudio = true
        
        // Stop any existing audio first
        if let existingPlayer = audioPlayer {
            print("AudioPlayback: Stopping existing audio player")
            existingPlayer.stop()
            audioPlayer = nil
            audioPlayerDelegate = nil
        }
        
        // If no audio asset exists, generate it first
        if sentence.audioAsset == nil {
            print("AudioPlayback: No audio asset found, generating new audio")
            Task {
                await generateAudioIfNeeded()
                print("AudioPlayback: Audio generation completed, audioAsset: \(sentence.audioAsset != nil ? "exists" : "nil")")
                // After generation, try playing again
                await MainActor.run {
                    self.isPreparingAudio = false
                    if self.sentence.audioAsset != nil {
                        print("AudioPlayback: Starting playback after generation")
                        self.playGeneratedAudio()
                    }
                }
            }
            return
        }
        
        // Audio asset exists, play it
        isPreparingAudio = false
        playGeneratedAudio()
    }
    
    private func playGeneratedAudio() {
        // Clear preparing flag when we start actual playback
        isPreparingAudio = false
        
        guard let audioAsset = sentence.audioAsset else {
            print("AudioPlayback: No audio asset to play")
            return
        }
        
        print("AudioPlayback: Playing audio asset at URL: \(audioAsset.fileURL)")
        print("AudioPlayback: Audio file exists: \(FileManager.default.fileExists(atPath: audioAsset.fileURL.path))")
        
        do {
            // Reset and configure audio session each time
            print("AudioPlayback: Configuring audio session")
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true, options: [])
            print("AudioPlayback: Audio session configured successfully")
            
            print("AudioPlayback: Creating new AVAudioPlayer")
            audioPlayer = try AVAudioPlayer(contentsOf: audioAsset.fileURL)
            
            guard let player = audioPlayer else {
                print("AudioPlayback: Failed to create audioPlayer")
                return
            }
            
            print("AudioPlayback: AVAudioPlayer created successfully")
            print("AudioPlayback: Audio duration: \(player.duration) seconds")
            print("AudioPlayback: Audio format: \(player.format.description)")
            
            // Create and retain delegate to prevent deallocation
            audioPlayerDelegate = AudioPlayerDelegate { [weak self] in
                print("AudioPlayback: DELEGATE CALLBACK - Audio playback finished for sentence: \(self?.sentence.id ?? UUID())")
                print("AudioPlayback: DELEGATE CALLBACK - Current isPlaying before reset: \(self?.isPlaying ?? false)")
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.onAudioStateChange?(self?.sentence.id ?? UUID(), false)
                    self?.audioPlayer = nil
                    self?.audioPlayerDelegate = nil
                    print("AudioPlayback: DELEGATE CALLBACK - Cleanup completed, isPlaying set to false")
                }
            }
            player.delegate = audioPlayerDelegate
            
            let prepareResult = player.prepareToPlay()
            print("AudioPlayback: Prepare to play result: \(prepareResult)")
            
            let playResult = player.play()
            print("AudioPlayback: Play result: \(playResult)")
            print("AudioPlayback: Player is playing: \(player.isPlaying)")
            
            if playResult {
                isPlaying = true
                print("AudioPlayback: Audio playback started successfully, isPlaying set to true")
            } else {
                print("AudioPlayback: Failed to start audio playback")
                audioPlayer = nil
                audioPlayerDelegate = nil
                isPlaying = false
                onAudioStateChange?(sentence.id, false)
            }
            
        } catch let error as NSError {
            print("AudioPlayback: Failed to create AVAudioPlayer: \(error)")
            print("AudioPlayback: Error domain: \(error.domain)")
            print("AudioPlayback: Error code: \(error.code)")
            print("AudioPlayback: Error details: \(error.localizedDescription)")
            print("AudioPlayback: Error user info: \(error.userInfo)")
            audioPlayer = nil
            audioPlayerDelegate = nil
            isPlaying = false
            onAudioStateChange?(sentence.id, false)
        }
    }
    
    private func pauseAudio() {
        print("AudioPlayback: pauseAudio called for sentence: \(sentence.id)")
        print("AudioPlayback: audioPlayer exists: \(audioPlayer != nil)")
        print("AudioPlayback: audioPlayer is playing: \(audioPlayer?.isPlaying ?? false)")
        
        if let player = audioPlayer {
            player.pause()
            print("AudioPlayback: Audio player paused")
        }
        
        isPlaying = false
        onAudioStateChange?(sentence.id, false)
        print("AudioPlayback: isPlaying set to false")
    }
    
    func stopAudio() {
        print("AudioPlayback: stopAudio called for sentence: \(sentence.id)")
        if let player = audioPlayer {
            player.stop()
            print("AudioPlayback: Audio player stopped")
        }
        audioPlayer = nil
        audioPlayerDelegate = nil
        isPlaying = false
        isPreparingAudio = false
        onAudioStateChange?(sentence.id, false)
        print("AudioPlayback: Audio stopped and cleaned up")
    }
}

private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("AudioPlayback: DELEGATE - audioPlayerDidFinishPlaying called, successfully: \(flag)")
        onFinish()
    }
}