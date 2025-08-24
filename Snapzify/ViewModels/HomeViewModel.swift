import Foundation
import SwiftUI
import Photos
import os.log

@MainActor
class HomeViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "HomeViewModel")
    @Published var documents: [Document] = []
    @Published var savedDocuments: [Document] = []
    @Published var shouldSuggestLatest = false
    @Published var latestInfo: LatestScreenshotInfo?
    @Published var isProcessing = false
    @Published var isLoading = true
    @Published var showPhotoPicker = false
    @Published var errorMessage: String?
    
    private var hasLoadedDocuments = false
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    private let segmentationService: SentenceSegmentationService
    private let pinyinService: PinyinService
    private let chineseProcessingService: ChineseProcessingService
    private let streamingChineseProcessingService: StreamingChineseProcessingService
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
        self.chineseProcessingService = ChineseProcessingService(configService: ConfigServiceImpl())
        self.streamingChineseProcessingService = StreamingChineseProcessingService(configService: ConfigServiceImpl())
        self.onOpenSettings = onOpenSettings
        self.onOpenDocument = onOpenDocument
    }
    
    func loadDocuments() async {
        // Only load if we haven't loaded yet
        guard !hasLoadedDocuments else { return }
        
        isLoading = true
        do {
            documents = try await store.fetchAll()
            savedDocuments = try await store.fetchSaved()
            await checkForLatestScreenshot()
            hasLoadedDocuments = true
        } catch {
            print("Failed to load documents: \(error)")
        }
        isLoading = false
    }
    
    func refreshDocuments() async {
        // Force refresh documents (for when we actually need to reload)
        isLoading = true
        do {
            documents = try await store.fetchAll()
            savedDocuments = try await store.fetchSaved()
            await checkForLatestScreenshot()
        } catch {
            print("Failed to load documents: \(error)")
        }
        isLoading = false
    }
    
    func refreshSavedDocuments() async {
        // Refresh only saved documents and sentences (for when returning from document view)
        do {
            documents = try await store.fetchAll()
            savedDocuments = try await store.fetchSaved()
        } catch {
            print("Failed to refresh saved documents: \(error)")
        }
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
                
                // Add 60-second timeout to image processing
                let document = try await withTimeout(seconds: 60) {
                    try await self.processImage(image, source: .photos)
                }
                
                try await store.save(document)
                shouldSuggestLatest = false
                
                // Navigate directly to the document view
                onOpenDocument(document)
                
                // Update documents list after navigation
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                await refreshDocuments()
            } catch {
                print("Failed to snapzify screenshot: \(error)")
                await MainActor.run {
                    if error is TimeoutError {
                        errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                    } else if let processingError = error as? ProcessingError {
                        errorMessage = processingError.errorDescription ?? "Failed to process image"
                        print("Setting error message: \(errorMessage ?? "")")
                    } else {
                        errorMessage = "Failed to snapzify screenshot: \(error.localizedDescription)"
                    }
                    logger.debug("Error message set to: \(self.errorMessage ?? "nil")")
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
                // Add 60-second timeout to image processing
                let document = try await withTimeout(seconds: 60) {
                    try await self.processImage(image, source: .imported)
                }
                
                try await store.save(document)
                
                // Navigate directly to the document view
                onOpenDocument(document)
                
                // Update documents list after navigation
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                await refreshDocuments()
            } catch {
                logger.error("Failed to snapzify pasted image: \(error.localizedDescription)")
                await MainActor.run {
                    if error is TimeoutError {
                        errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                    } else if let processingError = error as? ProcessingError {
                        errorMessage = processingError.errorDescription ?? "Failed to process image"
                        logger.debug("Setting error message for pasted image: \(self.errorMessage ?? "")")
                    } else {
                        errorMessage = "Failed to paste image: \(error.localizedDescription)"
                    }
                    logger.debug("Error message set to: \(self.errorMessage ?? "nil")")
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
                    logger.debug("Snapzifying completed, updating UI")
                    isProcessing = false
                }
            }
            
            do {
                logger.info("Starting image snapzifying")
                logger.debug("Calling OCR service")
                
                // Add 60-second timeout to image processing
                let document = try await withTimeout(seconds: 60) {
                    try await self.processImage(image, source: .imported)
                }
                
                // Document is already saved and navigation happens inside processImage
                // No need to save again here
                logger.info("Snapzifying completed, updating UI")
                
                // Update documents list after navigation
                await refreshDocuments()
                logger.debug("Documents reloaded")
            } catch {
                logger.error("Failed to snapzify picked image: \(error.localizedDescription)")
                await MainActor.run {
                    if error is TimeoutError {
                        errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                    } else if let processingError = error as? ProcessingError {
                        errorMessage = processingError.errorDescription ?? "Failed to process image"
                        logger.debug("Setting error message for picked image: \(self.errorMessage ?? "")")
                    } else {
                        errorMessage = "Failed to snapzify image: \(error.localizedDescription)"
                    }
                    logger.debug("Error message set to: \(self.errorMessage ?? "nil")")
                }
            }
        }
    }
    
    func processSharedImage(_ image: UIImage) async {
        // Process shared image in background without navigation
        do {
            logger.info("Processing shared image from extension")
            
            let script = ChineseScript(rawValue: selectedScript) ?? .simplified
            
            // Process the image using the same logic but without navigation
            _ = try await processImageWithoutNavigation(image, source: .shareExtension, script: script)
            
            logger.info("Shared image processed successfully")
            
            // Refresh documents list to show the new one
            await refreshDocuments()
        } catch {
            logger.error("Failed to process shared image: \(error.localizedDescription)")
        }
    }
    
    private func processImageWithoutNavigation(_ image: UIImage, source: DocumentSource, script: ChineseScript) async throws -> Document {
        logger.info("About to call OCR service")
        let ocrLines = try await ocrService.recognizeText(in: image)
        logger.info("OCR completed, got \(ocrLines.count) lines")
        
        var sentences: [Sentence] = []
        var chineseLinesToProcess: [String] = []
        var chineseLineIndices: [Int] = []
        
        // First pass: collect all Chinese lines that need processing
        for (_, line) in ocrLines.enumerated() {
            // Check if line contains parsed data (chinese|pinyin|english format)
            let components = line.text.components(separatedBy: "|")
            
            if components.count == 3 {
                // This is parsed data - handle separately
                let chinese = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let pinyin = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let english = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                
                if containsChinese(chinese) {
                    let normalizedChinese = script == .simplified ?
                        scriptConversionService.toSimplified(chinese) :
                        scriptConversionService.toTraditional(chinese)
                    
                    sentences.append(Sentence(
                        text: normalizedChinese,
                        rangeInImage: nil,
                        tokens: [],
                        pinyin: [pinyin],
                        english: english,
                        status: .translated
                    ))
                }
            } else if containsChinese(line.text) {
                // Collect Chinese lines for batch processing
                let normalizedText = script == .simplified ?
                    scriptConversionService.toSimplified(line.text) :
                    scriptConversionService.toTraditional(line.text)
                
                chineseLinesToProcess.append(normalizedText)
                chineseLineIndices.append(sentences.count)
                
                // Add placeholder sentence with "Generating..." status
                sentences.append(Sentence(
                    text: normalizedText,
                    rangeInImage: nil,
                    tokens: [],
                    pinyin: [],
                    english: "Generating...",
                    status: .ocrOnly
                ))
            }
        }
        
        // Check if we have any Chinese content
        let hasChineseContent = !sentences.isEmpty
        
        // If no Chinese content found, throw an error
        if !hasChineseContent {
            logger.warning("No Chinese content detected, throwing error")
            throw ProcessingError.noChineseDetected
        }
        
        // Create document with initial sentences (including placeholders)
        logger.info("Created document with \(sentences.count) sentences")
        
        let document = Document(
            source: source,
            script: script,
            sentences: sentences,
            imageData: image.pngData()
        )
        
        // Save document without navigation
        try await store.save(document)
        let savedDocument = document
        
        // Second pass: stream process Chinese lines with concurrent requests
        if !chineseLinesToProcess.isEmpty {
            logger.info("Stream processing \(chineseLinesToProcess.count) Chinese lines")
            
            do {
                // Store a reference to the document for updates
                var documentToUpdate = savedDocument
                
                try await streamingChineseProcessingService.processStreamingBatch(
                    chineseLinesToProcess,
                    script: script
                ) { [weak self] processed in
                    guard let self = self else { return }
                    
                    // Update sentence as soon as it's processed
                    let sentenceIndex = chineseLineIndices[processed.index]
                    sentences[sentenceIndex] = Sentence(
                        text: processed.chinese,
                        rangeInImage: nil,
                        tokens: [],
                        pinyin: processed.pinyin,
                        english: processed.english,
                        status: .translated
                    )
                    
                    // Update the document
                    documentToUpdate.sentences = sentences
                    
                    // Update in store
                    Task {
                        try? await self.store.update(documentToUpdate)
                    }
                }
            } catch {
                logger.error("Stream processing failed: \(error.localizedDescription)")
                // Fall back to regular batch processing
                do {
                    let processedBatch = try await chineseProcessingService.processBatch(chineseLinesToProcess, script: script)
                    
                    for (batchIndex, sentenceIndex) in chineseLineIndices.enumerated() {
                        if batchIndex < processedBatch.count {
                            let processed = processedBatch[batchIndex]
                            sentences[sentenceIndex] = Sentence(
                                text: processed.chinese,
                                rangeInImage: nil,
                                tokens: [],
                                pinyin: processed.pinyin,
                                english: processed.english,
                                status: .translated
                            )
                        }
                    }
                    
                    // Update document with final sentences
                    var updatedDocument = savedDocument
                    updatedDocument.sentences = sentences
                    _ = try? await store.update(updatedDocument)
                } catch {
                    logger.error("Fallback batch processing also failed: \(error.localizedDescription)")
                }
            }
        }
        
        return savedDocument
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
    
    private func containsChinese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for CJK Unified Ideographs ranges
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) ||
               (0x2A700...0x2B73F).contains(scalar.value) ||
               (0x2B740...0x2B81F).contains(scalar.value) ||
               (0x2B820...0x2CEAF).contains(scalar.value) ||
               (0x2CEB0...0x2EBEF).contains(scalar.value) ||
               (0x30000...0x3134F).contains(scalar.value) {
                return true
            }
        }
        return false
    }
    
    private func processImage(_ image: UIImage, source: DocumentSource) async throws -> Document {
        let script = ChineseScript(rawValue: selectedScript) ?? .simplified
        
        logger.info("About to call OCR service")
        let ocrLines = try await ocrService.recognizeText(in: image)
        logger.info("OCR completed, got \(ocrLines.count) lines")
        
        var sentences: [Sentence] = []
        var chineseLinesToProcess: [String] = []
        var chineseLineIndices: [Int] = []
        
        // First pass: collect all Chinese lines that need processing
        for (_, line) in ocrLines.enumerated() {
            // Check if line contains parsed data (chinese|pinyin|english format)
            let components = line.text.components(separatedBy: "|")
            
            if components.count == 3 {
                // This is parsed data - handle separately
                let chinese = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let pinyin = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let english = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                
                if containsChinese(chinese) {
                    let normalizedChinese = script == .simplified ?
                        scriptConversionService.toSimplified(chinese) :
                        scriptConversionService.toTraditional(chinese)
                    
                    sentences.append(Sentence(
                        text: normalizedChinese,
                        rangeInImage: nil,
                        tokens: [],
                        pinyin: [pinyin],
                        english: english,
                        status: .translated
                    ))
                }
            } else if containsChinese(line.text) {
                // Collect Chinese lines for batch processing
                let normalizedText = script == .simplified ?
                    scriptConversionService.toSimplified(line.text) :
                    scriptConversionService.toTraditional(line.text)
                
                chineseLinesToProcess.append(normalizedText)
                chineseLineIndices.append(sentences.count)
                
                // Add placeholder sentence with "Generating..." status
                sentences.append(Sentence(
                    text: normalizedText,
                    rangeInImage: nil,
                    tokens: [],
                    pinyin: [],
                    english: "Generating...",
                    status: .ocrOnly
                ))
            }
        }
        
        // Check if we have any Chinese content
        let hasChineseContent = !sentences.isEmpty
        
        // If no Chinese content found, throw an error
        if !hasChineseContent {
            logger.warning("No Chinese content detected, throwing error")
            throw ProcessingError.noChineseDetected
        }
        
        // Create document with initial sentences (including placeholders)
        logger.info("Created document with \(sentences.count) sentences")
        
        let document = Document(
            source: source,
            script: script,
            sentences: sentences,
            imageData: image.pngData()
        )
        
        // Save document and navigate to it immediately after OCR
        try await store.save(document)
        let savedDocument = document
        
        // Navigate to document view
        await MainActor.run {
            self.onOpenDocument(savedDocument)
        }
        
        // Second pass: stream process Chinese lines with concurrent requests
        if !chineseLinesToProcess.isEmpty {
            logger.info("Stream processing \(chineseLinesToProcess.count) Chinese lines")
            
            do {
                // Store a reference to the document for updates
                var documentToUpdate = savedDocument
                
                try await streamingChineseProcessingService.processStreamingBatch(
                    chineseLinesToProcess,
                    script: script
                ) { [weak self] processed in
                    guard let self = self else { return }
                    
                    // Update sentence as soon as it's processed
                    let sentenceIndex = chineseLineIndices[processed.index]
                    sentences[sentenceIndex] = Sentence(
                        text: processed.chinese,
                        rangeInImage: nil,
                        tokens: [],
                        pinyin: processed.pinyin,
                        english: processed.english,
                        status: .translated
                    )
                    
                    // Update the document
                    documentToUpdate.sentences = sentences
                    
                    // Defer the store update to avoid publishing changes within view updates
                    Task.detached { @MainActor in
                        do {
                            try await self.store.update(documentToUpdate)
                            self.logger.debug("Updated sentence \(processed.index + 1)/\(chineseLinesToProcess.count)")
                        } catch {
                            self.logger.error("Failed to update document: \(error)")
                        }
                    }
                }
            } catch {
                logger.error("Stream processing failed: \(error.localizedDescription)")
                // Fall back to regular batch processing
                do {
                    let processedBatch = try await chineseProcessingService.processBatch(chineseLinesToProcess, script: script)
                    
                    for (batchIndex, sentenceIndex) in chineseLineIndices.enumerated() {
                        if batchIndex < processedBatch.count {
                            let processed = processedBatch[batchIndex]
                            sentences[sentenceIndex] = Sentence(
                                text: processed.chinese,
                                rangeInImage: nil,
                                tokens: [],
                                pinyin: processed.pinyin,
                                english: processed.english,
                                status: .translated
                            )
                        }
                    }
                    
                    // Update document with final sentences
                    var updatedDocument = savedDocument
                    updatedDocument.sentences = sentences
                    _ = try? await store.update(updatedDocument)
                } catch {
                    logger.error("Fallback batch processing also failed: \(error.localizedDescription)")
                }
            }
        }
        
        return savedDocument
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

enum ProcessingError: Error, LocalizedError {
    case imageLoadFailed
    case noChineseDetected
    
    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Failed to load image"
        case .noChineseDetected:
            return "Unsnapzify-able!"
        }
    }
}
