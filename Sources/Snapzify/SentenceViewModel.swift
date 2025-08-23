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
    private let onUpdate: (Sentence) -> Void
    
    private var audioPlayer: AVAudioPlayer?
    
    init(
        sentence: Sentence,
        script: ChineseScript,
        translationService: TranslationService,
        ttsService: TTSService,
        autoTranslate: Bool,
        autoGenerateAudio: Bool,
        onUpdate: @escaping (Sentence) -> Void
    ) {
        self.sentence = sentence
        self.script = script
        self.translationService = translationService
        self.ttsService = ttsService
        self.autoTranslate = autoTranslate
        self.autoGenerateAudio = autoGenerateAudio
        self.onUpdate = onUpdate
    }
    
    func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded.toggle()
            
            if isExpanded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                
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
        guard sentence.audioAsset == nil,
              ttsService.isConfigured() else { return }
        
        isGeneratingAudio = true
        defer { isGeneratingAudio = false }
        
        do {
            let audioAsset = try await ttsService.generateAudio(for: sentence.text, script: script)
            sentence.audioAsset = audioAsset
            onUpdate(sentence)
        } catch {
            print("Audio generation failed: \(error)")
        }
    }
    
    func openInPleco() {
        if let url = URL(string: "plecoapi://x-callback-url/s?q=\(sentence.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }
    
    func playOrPauseAudio() {
        if isPlaying {
            pauseAudio()
        } else {
            playAudio()
        }
    }
    
    private func playAudio() {
        guard let audioAsset = sentence.audioAsset else {
            Task {
                await generateAudioIfNeeded()
                if sentence.audioAsset != nil {
                    playAudio()
                }
            }
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioAsset.fileURL)
            audioPlayer?.delegate = AudioPlayerDelegate { [weak self] in
                self?.isPlaying = false
            }
            audioPlayer?.play()
            isPlaying = true
            
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    private func pauseAudio() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func togglePin() {
        sentence.isPinned.toggle()
        onUpdate(sentence)
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
        onFinish()
    }
}