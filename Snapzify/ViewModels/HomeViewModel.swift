import Foundation
import SwiftUI
import Photos

@MainActor
class HomeViewModel: ObservableObject {
    @Published var documents: [Document] = []
    @Published var savedDocuments: [Document] = []
    @Published var savedSentences: [Sentence] = []
    @Published var shouldSuggestLatest = false
    @Published var latestInfo: LatestScreenshotInfo?
    @Published var isProcessing = false
    @Published var isLoading = true
    @Published var showPhotoPicker = false
    @Published var errorMessage: String?
    @Published var expandedSentenceIds: Set<UUID> = []
    
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    private let segmentationService: SentenceSegmentationService
    private let pinyinService: PinyinService
    private let onOpenSettings: () -> Void
    private let onOpenDocument: (Document) -> Void
    @AppStorage("selectedScript") private var selectedScript: String = ChineseScript.simplified.rawValue
    
    struct LatestScreenshotInfo {
        let timestamp: String
        let asset: PHAsset
    }
    
    init(
        store: DocumentStore,
        ocrService: OCRService,
        scriptConversionService: ScriptConversionService,
        segmentationService: SentenceSegmentationService,
        pinyinService: PinyinService,
        onOpenSettings: @escaping () -> Void,
        onOpenDocument: @escaping (Document) -> Void
    ) {
        self.store = store
        self.ocrService = ocrService
        self.scriptConversionService = scriptConversionService
        self.segmentationService = segmentationService
        self.pinyinService = pinyinService
        self.onOpenSettings = onOpenSettings
        self.onOpenDocument = onOpenDocument
    }
    
    func loadDocuments() async {
        isLoading = true
        do {
            documents = try await store.fetchAll()
            savedDocuments = try await store.fetchSaved()
            savedSentences = try await store.fetchSavedSentences()
            await checkForLatestScreenshot()
        } catch {
            print("Failed to load documents: \(error)")
        }
        isLoading = false
    }
    
    func checkForLatestScreenshot() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        // Remove screenshot filter to get most recent image from gallery
        // fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %ld", PHAssetMediaSubtype.photoScreenshot.rawValue)
        
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        guard let latestAsset = assets.firstObject else {
            shouldSuggestLatest = false
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        
        latestInfo = LatestScreenshotInfo(
            timestamp: formatter.string(from: latestAsset.creationDate ?? Date()),
            asset: latestAsset
        )
        
        // Only show smart banner if image is newer than last processed
        if let lastProcessed = documents.first,
           let assetDate = latestAsset.creationDate,
           assetDate <= lastProcessed.createdAt {
            shouldSuggestLatest = false
        } else {
            shouldSuggestLatest = true
        }
    }
    
    func processLatest() {
        guard let info = latestInfo else { return }
        
        Task {
            isProcessing = true
            defer { isProcessing = false }
            
            do {
                let image = try await loadImage(from: info.asset)
                
                // Add 10-second timeout to image processing
                let document = try await withTimeout(seconds: 10) {
                    try await self.processImage(image, source: .photos)
                }
                
                try await store.save(document)
                shouldSuggestLatest = false
                
                // Navigate directly to the document view
                onOpenDocument(document)
                
                // Update documents list after navigation
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                await loadDocuments()
            } catch {
                print("Failed to snapzify screenshot: \(error)")
                if error is TimeoutError {
                    await MainActor.run {
                        errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                    }
                }
            }
        }
    }
    
    func pasteImage() {
        guard let image = UIPasteboard.general.image else { return }
        
        Task {
            isProcessing = true
            defer { isProcessing = false }
            
            do {
                // Add 10-second timeout to image processing
                let document = try await withTimeout(seconds: 10) {
                    try await self.processImage(image, source: .imported)
                }
                
                try await store.save(document)
                
                // Navigate directly to the document view
                onOpenDocument(document)
                
                // Update documents list after navigation
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                await loadDocuments()
            } catch {
                print("Failed to snapzify pasted image: \(error)")
                if error is TimeoutError {
                    await MainActor.run {
                        errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                    }
                }
            }
        }
    }
    
    func pickScreenshot() {
        showPhotoPicker = true
    }
    
    func processPickedImage(_ image: UIImage) {
        Task {
            await MainActor.run {
                isProcessing = true
                errorMessage = nil
            }
            
            defer {
                Task { @MainActor in
                    print("Snapzifying completed, updating UI...")
                    isProcessing = false
                }
            }
            
            do {
                print("Starting image snapzifying...")
                print("Calling OCR service...")
                
                // Add 10-second timeout to image processing
                let document = try await withTimeout(seconds: 10) {
                    try await self.processImage(image, source: .imported)
                }
                
                print("Image snapzified, saving document with \(document.sentences.count) sentences...")
                try await store.save(document)
                print("Document saved successfully")
                
                // Navigate directly to the document view
                await MainActor.run {
                    onOpenDocument(document)
                }
                
                // Update documents list after navigation
                print("Waiting for navigation...")
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                await loadDocuments()
                print("Documents reloaded")
            } catch {
                print("Failed to snapzify picked image: \(error)")
                await MainActor.run {
                    if error is TimeoutError {
                        errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                    } else {
                        errorMessage = "Failed to snapzify image: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func open(_ document: Document) {
        onOpenDocument(document)
    }
    
    func openSettings() {
        onOpenSettings()
    }
    
    
    func translatedCount(for document: Document) -> Int {
        document.sentences.filter { $0.status == .translated }.count
    }
    
    private func loadImage(from asset: PHAsset) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if let image = image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ProcessingError.imageLoadFailed)
                }
            }
        }
    }
    
    private func processImage(_ image: UIImage, source: DocumentSource) async throws -> Document {
        let script = ChineseScript(rawValue: selectedScript) ?? .simplified
        
        print("ProcessImage: About to call OCR service...")
        let ocrLines = try await ocrService.recognizeText(in: image)
        print("ProcessImage: OCR completed, got \(ocrLines.count) lines")
        
        var sentences: [Sentence] = []
        
        for (index, line) in ocrLines.enumerated() {
            print("ProcessImage: Processing line \(index + 1)/\(ocrLines.count)")
            
            // Check if line contains parsed data (chinese|pinyin|english format)
            let components = line.text.components(separatedBy: "|")
            
            if components.count == 3 {
                // This is parsed data from ChatGPT
                let chinese = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let pinyin = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let english = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("ProcessImage: Found parsed data - Chinese: \(chinese.prefix(20))...")
                
                // Apply script conversion if needed
                let normalizedChinese = script == .simplified ?
                    scriptConversionService.toSimplified(chinese) :
                    scriptConversionService.toTraditional(chinese)
                
                sentences.append(Sentence(
                    text: normalizedChinese,
                    rangeInImage: nil,
                    tokens: [],  // No tokens needed
                    pinyin: [pinyin],  // Already formatted pinyin
                    english: english,  // Already have English translation
                    status: .translated  // Mark as translated since we have English
                ))
            } else {
                // Fallback for basic OCR text
                print("ProcessImage: Processing fallback text: \(line.text.prefix(20))...")
                
                let normalizedText = script == .simplified ?
                    scriptConversionService.toSimplified(line.text) :
                    scriptConversionService.toTraditional(line.text)
                
                sentences.append(Sentence(
                    text: normalizedText,
                    rangeInImage: nil,
                    tokens: [],
                    pinyin: [],  // No pinyin in fallback
                    english: nil,  // No English in fallback
                    status: .ocrOnly
                ))
            }
        }
        
        print("ProcessImage: Created document with \(sentences.count) sentences")
        
        return Document(
            source: source,
            script: script,
            sentences: sentences,
            imageData: image.pngData()
        )
    }
}

// MARK: - Timeout Utilities

struct TimeoutError: Error, LocalizedError {
    let seconds: TimeInterval
    
    var errorDescription: String? {
        "Operation timed out after \(seconds) seconds"
    }
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the main operation
        group.addTask {
            try await operation()
        }
        
        // Add the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError(seconds: seconds)
        }
        
        // Return the first result (either success or timeout)
        let result = try await group.next()!
        group.cancelAll() // Cancel the remaining task
        return result
    }
}

enum ProcessingError: Error {
    case imageLoadFailed
}