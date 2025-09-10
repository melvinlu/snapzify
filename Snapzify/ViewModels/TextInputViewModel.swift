import Foundation
import SwiftUI

@MainActor
class TextInputViewModel: ObservableObject {
    @Published var inputText: String = "" {
        didSet {
            updateHasInput()
        }
    }
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var streamingResult: String = ""
    @Published var isStreaming: Bool = false
    @Published private(set) var hasInput: Bool = false
    
    private let translationService: EnglishToChineseTranslationService
    private let documentService: DocumentService
    private let appState: AppState
    
    init(
        translationService: EnglishToChineseTranslationService,
        documentService: DocumentService,
        appState: AppState
    ) {
        self.translationService = translationService
        self.documentService = documentService
        self.appState = appState
    }
    
    private func updateHasInput() {
        hasInput = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isServiceConfigured: Bool {
        translationService.isConfigured()
    }
    
    func streamTranslate() async {
        guard hasInput else { return }
        
        await MainActor.run {
            isStreaming = true
            errorMessage = nil
            streamingResult = ""
        }
        
        do {
            let stream = translationService.streamTranslate(inputText)
            
            for try await chunk in stream {
                await MainActor.run {
                    self.streamingResult += chunk
                }
            }
            
            await MainActor.run {
                self.isStreaming = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isStreaming = false
            }
        }
    }
    
    func processAndSaveTranslation() async {
        guard !streamingResult.isEmpty else { return }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            // Extract the first Chinese translation from the streamed result
            // This is a simplified extraction - you might want to parse more carefully
            let lines = streamingResult.components(separatedBy: "\n")
            var chineseText = ""
            
            for line in lines {
                if line.contains("**1.") {
                    // Extract Chinese characters from first translation
                    if let start = line.firstIndex(of: "."),
                       let end = line.firstIndex(of: "(") {
                        let startIndex = line.index(after: start)
                        chineseText = String(line[startIndex..<end]).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }
            
            if chineseText.isEmpty {
                chineseText = "Translation result"
            }
            
            // Create sentence from the result
            let sentence = Sentence(
                text: chineseText,
                status: .translated
            )
            
            // Create a new document
            let document = Document(
                id: UUID(),
                createdAt: Date(),
                source: .textInput,
                script: .simplified,
                sentences: [sentence],
                mediaURL: nil,
                thumbnailURL: nil,
                isVideo: false,
                isSaved: false,
                assetIdentifier: nil,
                customName: "\(inputText) → \(chineseText)",
                additionalInfo: streamingResult
            )
            
            // Save the document
            try await documentService.save(document)
            
            // Navigate to the document
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .openDocument,
                    object: document
                )
                
                // Clear the state
                self.clear()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save translation: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    func clear() {
        inputText = ""
        streamingResult = ""
        errorMessage = nil
        isLoading = false
        isStreaming = false
    }
    
    func dismissError() {
        errorMessage = nil
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let openDocument = Notification.Name("openDocument")
}