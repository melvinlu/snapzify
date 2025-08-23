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
    
    let script: ChineseScript
    private let translationService: TranslationService
    private let ttsService: TTSService
    private let autoTranslate: Bool
    private let autoGenerateAudio: Bool
    private let onToggleExpanded: (UUID, Bool) -> Void
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
                    if autoTranslate && sentence.english == nil {
                        await translateIfNeeded()
                    }
                    
                    if autoGenerateAudio && sentence.audioAsset == nil {
                        await generateAudioIfNeeded()
                    }
                }
            }
        }
    }
    
    func translateIfNeeded() async {
        guard sentence.english == nil,
              translationService.isConfigured() else { return }
        
        isTranslating = true
        defer { isTranslating = false }
        
        do {
            let translations = try await translationService.translate([sentence.text])
            
            if let translation = translations.first, let translation = translation {
                sentence.english = translation
                sentence.status = .translated
                onUpdate(sentence)
                
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            print("Translation failed: \(error)")
            sentence.status = .error("Translation failed")
            onUpdate(sentence)
        }
    }
    
    func generateAudioIfNeeded() async {
        print("AudioGeneration: generateAudioIfNeeded called")
        print("AudioGeneration: Current audioAsset: \(sentence.audioAsset != nil ? "exists" : "nil")")
        print("AudioGeneration: TTS configured: \(ttsService.isConfigured())")
        
        guard sentence.audioAsset == nil,
              ttsService.isConfigured() else { 
            print("AudioGeneration: Skipping generation - audioAsset exists or TTS not configured")
            return 
        }
        
        print("AudioGeneration: Starting audio generation for text: '\(sentence.text.prefix(50))...'")
        
        await MainActor.run {
            isGeneratingAudio = true
        }
        defer { 
            Task { @MainActor in
                isGeneratingAudio = false
                print("AudioGeneration: Generation completed, isGeneratingAudio set to false")
            }
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
                print("AudioGeneration: Audio asset saved to sentence")
            }
        } catch {
            print("AudioGeneration: Audio generation failed with error: \(error)")
            print("AudioGeneration: Error details: \(error.localizedDescription)")
            if let ttsError = error as? TTSError {
                print("AudioGeneration: TTS specific error: \(ttsError)")
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
        
        // Stop any existing audio first
        if let existingPlayer = audioPlayer {
            print("AudioPlayback: Stopping existing audio player")
            existingPlayer.stop()
            audioPlayer = nil
            audioPlayerDelegate = nil
        }
        
        guard let audioAsset = sentence.audioAsset else {
            print("AudioPlayback: No audio asset found, generating new audio")
            Task {
                await generateAudioIfNeeded()
                print("AudioPlayback: Audio generation completed, audioAsset: \(sentence.audioAsset != nil ? "exists" : "nil")")
                if sentence.audioAsset != nil {
                    await MainActor.run {
                        print("AudioPlayback: Starting playback after generation on MainActor")
                        playAudio()
                    }
                }
            }
            return
        }
        
        print("AudioPlayback: Found audio asset at URL: \(audioAsset.fileURL)")
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
        print("AudioPlayback: isPlaying set to false")
    }
    
    func toggleSave() {
        sentence.isSaved.toggle()
        onUpdate(sentence)
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