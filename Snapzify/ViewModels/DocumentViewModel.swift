import Foundation
import SwiftUI
import AVFoundation

@MainActor
class DocumentViewModel: ObservableObject {
    @Published var document: Document
    @Published var showOriginalImage = false
    @Published var selectedSentenceId: UUID?
    @Published var isTranslatingBatch = false
    @Published var expandedSentenceIds: Set<UUID> = []
    @Published var showDeleteImageAlert = false
    @Published var shouldDismiss = false
    
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
        let isExpanded = expandedSentenceIds.contains(sentence.id)
        return SentenceViewModel(
            sentence: sentence,
            script: document.script,
            translationService: translationService,
            ttsService: ttsService,
            autoTranslate: autoTranslate,
            autoGenerateAudio: autoGenerateAudio,
            isExpanded: isExpanded,
            onToggleExpanded: { [weak self] sentenceId, expanded in
                guard let self = self else { return }
                if expanded {
                    self.expandedSentenceIds.insert(sentenceId)
                } else {
                    self.expandedSentenceIds.remove(sentenceId)
                }
            }
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
    
    func toggleImageSave() {
        document.isSaved.toggle()
        Task {
            try? await store.update(document)
        }
    }
    
    func toggleExpandAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSentenceIds.count == document.sentences.count {
                // All are expanded, collapse all
                expandedSentenceIds.removeAll()
            } else {
                // Not all are expanded, expand all
                expandedSentenceIds = Set(document.sentences.map { $0.id })
            }
        }
    }
    
    var areAllExpanded: Bool {
        expandedSentenceIds.count == document.sentences.count
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
    
    func deleteImage() {
        Task {
            // Delete the entire document from storage
            try? await store.delete(id: document.id)
            
            // Notify that we should go back
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.shouldDismiss = true
                }
            }
        }
    }
}