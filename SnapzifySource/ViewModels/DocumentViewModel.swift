import Foundation
import SwiftUI
import AVFoundation

@MainActor
class DocumentViewModel: ObservableObject {
    @Published var document: Document
    @Published var showOriginalImage = false
    @Published var selectedSentenceId: UUID?
    @Published var isTranslatingBatch = false
    
    private let translationService: TranslationService
    private let ttsService: TTSService
    private let store: DocumentStore
    
    @AppStorage("autoTranslate") private var autoTranslate = true
    @AppStorage("autoGenerateAudio") private var autoGenerateAudio = true
    
    init(
        document: Document,
        translationService: TranslationService,
        ttsService: TTSService,
        store: DocumentStore
    ) {
        self.document = document
        self.translationService = translationService
        self.ttsService = ttsService
        self.store = store
    }
    
    func toggleImageVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showOriginalImage.toggle()
        }
    }
    
    func selectSentence(_ sentenceId: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if selectedSentenceId == sentenceId {
                selectedSentenceId = nil
            } else {
                selectedSentenceId = sentenceId
            }
        }
    }
    
    func translateAllPending() async {
        guard autoTranslate && translationService.isConfigured() else { return }
        
        isTranslatingBatch = true
        defer { isTranslatingBatch = false }
        
        let pendingSentences = document.sentences.filter { $0.english == nil }
        guard !pendingSentences.isEmpty else { return }
        
        let texts = pendingSentences.map { $0.text }
        
        do {
            let translations = try await translationService.translate(texts)
            
            for (index, translation) in translations.enumerated() {
                if let translation = translation,
                   let sentenceIndex = document.sentences.firstIndex(where: { $0.id == pendingSentences[index].id }) {
                    document.sentences[sentenceIndex].english = translation
                    document.sentences[sentenceIndex].status = .translated
                }
            }
            
            try await store.save(document)
        } catch {
            print("Translation failed: \(error)")
        }
    }
    
    func createSentenceViewModel(for sentence: Sentence) -> SentenceViewModel {
        SentenceViewModel(
            sentence: sentence,
            script: document.script,
            translationService: translationService,
            ttsService: ttsService,
            autoTranslate: autoTranslate,
            autoGenerateAudio: autoGenerateAudio
        ) { [weak self] updatedSentence in
            guard let self = self,
                  let index = self.document.sentences.firstIndex(where: { $0.id == updatedSentence.id }) else {
                return
            }
            
            self.document.sentences[index] = updatedSentence
            
            Task {
                try? await self.store.save(self.document)
            }
        }
    }
    
    func highlightedRegion(for sentenceId: UUID) -> CGRect? {
        guard showOriginalImage,
              let sentence = document.sentences.first(where: { $0.id == sentenceId }) else {
            return nil
        }
        return sentence.rangeInImage
    }
    
    func toggleImagePin() {
        document.isPinned.toggle()
        Task {
            try? await store.update(document)
        }
    }
    
    func toggleImageSave() {
        document.isSaved.toggle()
        Task {
            try? await store.update(document)
        }
    }
    
    func toggleSentencePin(sentenceId: UUID) {
        guard let index = document.sentences.firstIndex(where: { $0.id == sentenceId }) else {
            return
        }
        document.sentences[index].isPinned.toggle()
        Task {
            try? await store.update(document)
        }
    }
    
    func toggleSentenceSave(sentenceId: UUID) {
        guard let index = document.sentences.firstIndex(where: { $0.id == sentenceId }) else {
            return
        }
        document.sentences[index].isSaved.toggle()
        Task {
            try? await store.update(document)
        }
    }
}