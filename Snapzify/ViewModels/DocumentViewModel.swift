import Foundation
import SwiftUI
import AVFoundation
import Photos

extension Notification.Name {
    static let documentSavedStatusChanged = Notification.Name("documentSavedStatusChanged")
}

@MainActor
class DocumentViewModel: ObservableObject {
    @Published var document: Document
    @Published var selectedSentenceId: UUID?
    @Published var isTranslatingBatch = false
    @Published var showDeleteImageAlert = false
    @Published var shouldDismiss = false
    
    private let translationService: TranslationService
    private let ttsService: TTSService
    private let store: DocumentStore
    private var sentenceViewModels: [UUID: SentenceViewModel] = [:]
    private var currentlyPlayingSentenceId: UUID?
    
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
        
        let pendingSentences = document.sentences.filter { $0.status != .translated }
        guard !pendingSentences.isEmpty else { return }
        
        let texts = pendingSentences.map { $0.text }
        
        do {
            // Use ChineseProcessingService to get pinyin AND translations
            let chineseProcessor = ServiceContainer.shared.chineseProcessingService
            let processedResults = try await chineseProcessor.processBatch(texts, script: document.script)
            
            for (index, result) in processedResults.enumerated() {
                if let sentenceIndex = document.sentences.firstIndex(where: { $0.id == pendingSentences[index].id }) {
                    document.sentences[sentenceIndex].status = .translated
                }
            }
            
            try await store.save(document)
        } catch {
            print("Translation failed: \(error)")
        }
    }
    
    func createSentenceViewModel(for sentence: Sentence) -> SentenceViewModel {
        // Return cached view model if it exists
        if let cachedViewModel = sentenceViewModels[sentence.id] {
            // Only update sentence data if it has actually changed
            if cachedViewModel.sentence.audioAsset != sentence.audioAsset {
                cachedViewModel.sentence = sentence
            }
            return cachedViewModel
        }
        
        // Create new view model and cache it
        let viewModel = SentenceViewModel(
            sentence: sentence,
            script: document.script,
            translationService: translationService,
            ttsService: ttsService,
            autoTranslate: autoTranslate,
            autoGenerateAudio: autoGenerateAudio,
            isExpanded: false, // Not used in new design
            onToggleExpanded: { _, _ in }, // Not used
            onAudioStateChange: { [weak self] sentenceId, isPlaying in
                guard let self = self else { return }
                self.handleAudioStateChange(sentenceId: sentenceId, isPlaying: isPlaying)
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
        
        sentenceViewModels[sentence.id] = viewModel
        return viewModel
    }
    
    func highlightedRegion(for sentenceId: UUID) -> CGRect? {
        guard let sentence = document.sentences.first(where: { $0.id == sentenceId }) else {
            return nil
        }
        return sentence.rangeInImage
    }
    
    func toggleImageSave() {
        document.isSaved.toggle()
        
        // Post notification IMMEDIATELY for instant UI update
        NotificationCenter.default.post(name: .documentSavedStatusChanged, object: document)
        
        // Then update the database in background
        Task {
            try? await store.update(document)
        }
    }
    
    func renameDocument(_ newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        document.customName = trimmedName.isEmpty ? nil : trimmedName
        
        // Post notification for UI update
        NotificationCenter.default.post(name: .documentSavedStatusChanged, object: document)
        
        // Update the database
        Task {
            try? await store.update(document)
        }
    }
    
    func refreshDocument() async {
        print("📱 DocumentViewModel: Starting refresh for document \(document.id)")
        if let updatedDocument = try? await store.fetch(id: document.id) {
            await MainActor.run {
                print("📱 DocumentViewModel: Fetched document with \(updatedDocument.sentences.count) sentences")
                for (index, sentence) in updatedDocument.sentences.enumerated() {
                    print("📱   Sentence \(index): id=\(sentence.id), text='\(sentence.text)', status=\(sentence.status)")
                }
                // Update the entire document to trigger view updates
                self.document = updatedDocument
                print("📱 DocumentViewModel: Document updated")
            }
        } else {
            print("📱 DocumentViewModel: Failed to fetch document")
        }
    }
    
    private var refreshTask: Task<Void, Never>?
    
    func startRefreshTimer() {
        // Cancel any existing refresh task
        refreshTask?.cancel()
        
        refreshTask = Task {
            // Wait a bit before starting to refresh to let initial load complete
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second initial delay
            
            while !Task.isCancelled {
                await refreshDocument()
                
                // Stop refreshing once all sentences are translated
                let allTranslated = document.sentences.allSatisfy { sentence in
                    sentence.status == .translated
                }
                if allTranslated {
                    break
                }
                
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second between refreshes
            }
        }
    }
    
    
    
    func deleteImage() {
        Task {
            // First, try to delete from photo library if we have an asset identifier
            if let assetIdentifier = document.assetIdentifier {
                await deleteFromPhotoLibrary(assetIdentifier: assetIdentifier)
            }
            
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
    
    private func deleteFromPhotoLibrary(assetIdentifier: String) async {
        // Check photo library authorization status
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .notDetermined:
            // Request permission
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if newStatus == .authorized || newStatus == .limited {
                await performPhotoDelete(assetIdentifier: assetIdentifier)
            }
        case .authorized, .limited:
            // We have permission, proceed with deletion
            await performPhotoDelete(assetIdentifier: assetIdentifier)
        case .denied, .restricted:
            // Can't delete without permission
            print("Photo library permission denied, cannot delete photo from device")
        @unknown default:
            print("Unknown authorization status")
        }
    }
    
    private func performPhotoDelete(assetIdentifier: String) async {
        // Fetch the asset
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        
        guard let asset = fetchResult.firstObject else {
            print("Asset not found in photo library: \(assetIdentifier)")
            return
        }
        
        // Delete the asset
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets([asset] as NSFastEnumeration)
            }
            print("Successfully deleted photo from device library")
        } catch {
            print("Failed to delete photo from library: \(error)")
        }
    }
    
    private func handleAudioStateChange(sentenceId: UUID, isPlaying: Bool) {
        if isPlaying {
            // If another sentence is playing, stop it first
            if let currentId = currentlyPlayingSentenceId, currentId != sentenceId {
                if let currentViewModel = sentenceViewModels[currentId] {
                    currentViewModel.stopAudio()
                }
            }
            currentlyPlayingSentenceId = sentenceId
        } else if currentlyPlayingSentenceId == sentenceId {
            currentlyPlayingSentenceId = nil
        }
    }
}