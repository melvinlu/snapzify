import Foundation
import SwiftUI
import Photos
import AVFoundation
import os.log

@MainActor
class HomeViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "HomeViewModel")
    @Published var documents: [Document] = []
    @Published var savedDocuments: [Document] = []
    @Published var shouldSuggestLatest = false
    @Published var latestInfo: LatestScreenshotInfo?
    @Published var isProcessing = false
    @Published var isProcessingSharedImage = false
    @Published var isLoading = true
    @Published var showPhotoPicker = false
    @Published var errorMessage: String?
    
    private var hasLoadedDocuments = false
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    private let chineseProcessingService: ChineseProcessingService = ServiceContainer.shared.chineseProcessingService
    private let streamingChineseProcessingService: StreamingChineseProcessingService = ServiceContainer.shared.streamingChineseProcessingService
    var onOpenSettings: () -> Void
    var onOpenDocument: (Document) -> Void
    @AppStorage("selectedScript") private var selectedScript: String = ChineseScript.simplified.rawValue
    
    struct LatestScreenshotInfo {
        let timestamp: String
        let asset: PHAsset
    }
    
    init(
        store: DocumentStore,
        ocrService: OCRService,
        scriptConversionService: ScriptConversionService,
        onOpenSettings: @escaping () -> Void,
        onOpenDocument: @escaping (Document) -> Void
    ) {
        self.store = store
        self.ocrService = ocrService
        self.scriptConversionService = scriptConversionService
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
        // Force refresh documents WITHOUT showing loading state
        do {
            documents = try await store.fetchAll()
            savedDocuments = try await store.fetchSaved()
            await checkForLatestScreenshot()
        } catch {
            print("Failed to load documents: \(error)")
        }
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
    
    func updateDocumentSavedStatus(_ updatedDocument: Document) {
        // Instantly update the local arrays without waiting for database
        
        // Update in documents array
        if let index = documents.firstIndex(where: { $0.id == updatedDocument.id }) {
            documents[index] = updatedDocument
        }
        
        // Update saved documents array
        if updatedDocument.isSaved {
            // Add to saved if not already there
            if !savedDocuments.contains(where: { $0.id == updatedDocument.id }) {
                savedDocuments.append(updatedDocument)
                savedDocuments.sort { $0.createdAt > $1.createdAt }
            } else {
                // Update existing
                if let index = savedDocuments.firstIndex(where: { $0.id == updatedDocument.id }) {
                    savedDocuments[index] = updatedDocument
                }
            }
        } else {
            // Remove from saved
            savedDocuments.removeAll { $0.id == updatedDocument.id }
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
            // Note: isProcessing is cleared in processImage after document is created
            
            do {
                let image = try await loadImage(from: info.asset)
                
                // Add 60-second timeout to image processing
                _ = try await withTimeout(seconds: 60) {
                    try await self.processImage(image, source: .photos, assetIdentifier: info.asset.localIdentifier)
                }
                
                // Document is already saved in processImage
                shouldSuggestLatest = false
                
                // No need to refresh - document is already added to the list in processImage
            } catch {
                print("Failed to snapzify screenshot: \(error)")
                await MainActor.run {
                    isProcessing = false  // Clear on error
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
                _ = try await withTimeout(seconds: 60) {
                    try await self.processImage(image, source: .imported)
                }
                
                // Document is already saved and navigation happens inside processImage
                // Document is also already added to the list in processImage
            } catch {
                logger.error("Failed to snapzify pasted image: \(error.localizedDescription)")
                await MainActor.run {
                    isProcessing = false  // Clear on error
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
            // Note: isProcessing is cleared in processImage after document is created
            
            do {
                logger.info("Starting image snapzifying")
                logger.debug("Calling OCR service")
                
                // Add 60-second timeout to image processing
                _ = try await withTimeout(seconds: 60) {
                    try await self.processImage(image, source: .imported)
                }
                
                // Document is already saved and navigation happens inside processImage
                // Document is also already added to the list in processImage
                logger.info("Snapzifying completed, updating UI")
                logger.debug("Documents reloaded")
            } catch {
                logger.error("Failed to snapzify picked image: \(error.localizedDescription)")
                await MainActor.run {
                    isProcessing = false  // Clear on error
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
    
    func processPickedVideo(_ videoURL: URL) async {
        await MainActor.run {
            isProcessing = true
            errorMessage = nil
        }
        
        do {
            logger.info("Starting video processing from URL: \(videoURL)")
            
            // Extract frames from video
            // Extract frames every 0.2 seconds for real-time tappability
            let frames = try await extractFramesFromVideo(videoURL, frameInterval: 0.2)
            
            guard !frames.isEmpty else {
                throw ProcessingError.noFramesExtracted
            }
            
            logger.info("Extracted \(frames.count) frames from video")
            
            // Process all frames concurrently for OCR
            // Dictionary to track all appearances of each unique text
            var textAppearances: [String: [FrameAppearance]] = [:]
            let frameInterval = 0.2 // seconds between frames (must match extraction interval)
            
            logger.info("Starting concurrent OCR processing for \(frames.count) frames")
            
            // Process frames in concurrent batches to avoid overwhelming the API
            // Google Cloud Vision allows up to 30 requests per second by default
            let batchSize = 10 // Process 10 frames concurrently at a time
            
            for batchStart in stride(from: 0, to: frames.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, frames.count)
                let batch = Array(frames[batchStart..<batchEnd])
                let batchIndices = Array(batchStart..<batchEnd)
                
                logger.debug("Processing OCR batch: frames \(batchStart + 1)-\(batchEnd)/\(frames.count)")
                
                // Process this batch concurrently
                let batchResults = try await withThrowingTaskGroup(of: (Int, [OCRLine]).self) { group in
                    for (localIndex, frame) in batch.enumerated() {
                        let frameIndex = batchIndices[localIndex]
                        group.addTask {
                            let ocrLines = try await self.ocrService.recognizeText(in: frame)
                            return (frameIndex, ocrLines)
                        }
                    }
                    
                    var results: [(Int, [OCRLine])] = []
                    for try await result in group {
                        results.append(result)
                    }
                    return results
                }
                
                // Process results from this batch
                for (frameIndex, ocrLines) in batchResults {
                    let timestamp = Double(frameIndex) * frameInterval
                    
                    for line in ocrLines {
                        if containsChinese(line.text) {
                            let normalizedText = ChineseScript(rawValue: selectedScript) == .simplified ?
                                scriptConversionService.toSimplified(line.text) :
                                scriptConversionService.toTraditional(line.text)
                            
                            // Track this appearance
                            let appearance = FrameAppearance(timestamp: timestamp, bbox: line.bbox)
                            
                            if textAppearances[normalizedText] == nil {
                                textAppearances[normalizedText] = []
                            }
                            textAppearances[normalizedText]?.append(appearance)
                        }
                    }
                }
                
                // Small delay between batches to avoid rate limiting (optional, can be removed if not needed)
                if batchEnd < frames.count {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second pause between batches
                }
            }
            
            logger.info("Completed concurrent OCR processing for all frames")
            
            // Convert to sentences with all their frame appearances
            var allSentences: [Sentence] = []
            for (text, appearances) in textAppearances {
                // Use the first appearance's bbox as the primary one for compatibility
                let primaryBbox = appearances.first?.bbox
                
                allSentences.append(Sentence(
                    text: text,
                    rangeInImage: primaryBbox,
                    tokens: [],
                    pinyin: [],
                    english: nil, // Don't set "Generating..." - will translate on-demand
                    status: .ocrOnly,
                    timestamp: appearances.first?.timestamp, // Keep first timestamp for compatibility
                    frameAppearances: appearances // Store all appearances
                ))
            }
            
            guard !allSentences.isEmpty else {
                throw ProcessingError.noChineseDetected
            }
            
            logger.info("Found \(allSentences.count) unique Chinese sentences across all frames")
            
            // Skip translations - will be done on-demand
            let script = ChineseScript(rawValue: selectedScript) ?? .simplified
            
            // Use the first frame as the representative image
            let representativeImage = frames.first!
            
            // Load video data
            let videoData = try Data(contentsOf: videoURL)
            
            // Create document with OCR-only sentences (no translations yet)
            let document = Document(
                source: .imported,
                script: script,
                sentences: allSentences,
                imageData: representativeImage.pngData(),
                videoData: videoData,
                isVideo: true
            )
            
            try await store.save(document)
            let savedDocument = document
            
            // Navigate to the document after everything is processed
            await MainActor.run {
                self.documents.insert(savedDocument, at: 0)
                self.isProcessing = false
                self.onOpenDocument(savedDocument)
            }
            
            // Clean up temporary video file
            try? FileManager.default.removeItem(at: videoURL)
            
        } catch {
            logger.error("Failed to process video: \(error.localizedDescription)")
            await MainActor.run {
                isProcessing = false
                if error is TimeoutError {
                    errorMessage = "Video processing timed out. Please try a shorter video."
                } else if let processingError = error as? ProcessingError {
                    errorMessage = processingError.errorDescription ?? "Failed to process video"
                } else {
                    errorMessage = "Failed to process video: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func extractFramesFromVideo(_ url: URL, frameInterval: TimeInterval) async throws -> [UIImage] {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationInSeconds = CMTimeGetSeconds(duration)
        
        guard durationInSeconds > 0 else {
            throw ProcessingError.invalidVideo
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero
        
        var frames: [UIImage] = []
        var currentTime: TimeInterval = 0
        
        while currentTime < durationInSeconds {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                frames.append(uiImage)
            } catch {
                logger.warning("Failed to extract frame at \(currentTime)s: \(error)")
            }
            
            currentTime += frameInterval
            
            // Limit to 150 frames max to avoid memory issues (30 seconds at 0.2s intervals)
            if frames.count >= 150 {
                logger.info("Reached maximum frame limit (150)")
                break
            }
        }
        
        return frames
    }
    
    func processSharedImage(_ image: UIImage) async {
        // Process shared image with high priority
        await Task(priority: .high) {
            do {
                await MainActor.run {
                    logger.info("Processing shared image from extension")
                    isProcessingSharedImage = true
                }
                
                let script = ChineseScript(rawValue: selectedScript) ?? .simplified
                
                // Process the image and automatically navigate to it
                _ = try await processImageCore(
                    image,
                    source: .shareExtension,
                    script: script,
                    assetIdentifier: nil,
                    shouldNavigate: true  // Changed to true to auto-open document
                )
                
                await MainActor.run {
                    logger.info("Shared image processed successfully and opened")
                }
            } catch {
                await MainActor.run {
                    logger.error("Failed to process shared image: \(error.localizedDescription)")
                    isProcessingSharedImage = false
                }
            }
        }.value
    }
    
    func processActionExtensionImage(_ image: UIImage) async {
        // Process image from ActionExtension with high priority and auto-open
        await Task(priority: .high) {
            do {
                await MainActor.run {
                    logger.info("Processing image from ActionExtension")
                    isProcessing = true
                }
                
                let script = ChineseScript(rawValue: selectedScript) ?? .simplified
                
                // Process the image and automatically navigate to it
                _ = try await processImageCore(
                    image,
                    source: .imported,  // Using imported as source for ActionExtension
                    script: script,
                    assetIdentifier: nil,
                    shouldNavigate: true  // Auto-open document
                )
                
                await MainActor.run {
                    logger.info("ActionExtension image processed successfully and opened")
                }
            } catch {
                await MainActor.run {
                    logger.error("Failed to process ActionExtension image: \(error.localizedDescription)")
                    isProcessing = false
                    
                    if error is TimeoutError {
                        errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                    } else if let processingError = error as? ProcessingError {
                        errorMessage = processingError.errorDescription ?? "Failed to process image"
                    } else {
                        errorMessage = "Failed to process image: \(error.localizedDescription)"
                    }
                }
            }
        }.value
    }
    
    private func processImageWithoutNavigation(_ image: UIImage, source: DocumentSource, script: ChineseScript, assetIdentifier: String? = nil) async throws -> Document {
        return try await processImageCore(
            image,
            source: source,
            script: script,
            assetIdentifier: assetIdentifier,
            shouldNavigate: false
        )
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
    
    private func processImage(_ image: UIImage, source: DocumentSource, assetIdentifier: String? = nil) async throws -> Document {
        let script = ChineseScript(rawValue: selectedScript) ?? .simplified
        return try await processImageCore(
            image,
            source: source,
            script: script,
            assetIdentifier: assetIdentifier,
            shouldNavigate: true
        )
    }
    
    private func processImageCore(
        _ image: UIImage,
        source: DocumentSource,
        script: ChineseScript,
        assetIdentifier: String? = nil,
        shouldNavigate: Bool
    ) async throws -> Document {
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
                        rangeInImage: line.bbox, // Use the bbox from OCR
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
                let newSentence = Sentence(
                    text: normalizedText,
                    rangeInImage: line.bbox, // Use the bbox from OCR
                    tokens: [],
                    pinyin: [],
                    english: "Generating...",
                    status: .ocrOnly
                )
                logger.debug("📝 Created sentence with ID: \(newSentence.id)")
                sentences.append(newSentence)
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
            imageData: image.pngData(),
            assetIdentifier: assetIdentifier
        )
        
        // Save document
        try await store.save(document)
        let savedDocument = document
        
        // Handle navigation and UI updates
        await MainActor.run {
            // Add the document to the local documents array immediately
            self.documents.insert(savedDocument, at: 0)
            
            if shouldNavigate {
                logger.info("Calling onOpenDocument for document: \(savedDocument.id)")
                self.onOpenDocument(savedDocument)
                // Clear processing flag since document is now created and visible
                if source == .shareExtension {
                    self.isProcessingSharedImage = false
                } else {
                    self.isProcessing = false
                }
            } else if source == .shareExtension {
                // Clear processing flag for shared images since document is now visible
                self.isProcessingSharedImage = false
            }
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
                    
                    logger.info("🔄 Received processed sentence \(processed.index): english='\(processed.english)', pinyin=\(processed.pinyin)")
                    
                    // Update sentence as soon as it's processed
                    let sentenceIndex = chineseLineIndices[processed.index]
                    let originalSentence = sentences[sentenceIndex]
                    // Preserve the original ID and bbox
                    sentences[sentenceIndex] = Sentence(
                        id: originalSentence.id, // PRESERVE ORIGINAL ID!
                        text: processed.chinese,
                        rangeInImage: originalSentence.rangeInImage, // Keep the original bbox
                        tokens: [],
                        pinyin: processed.pinyin,
                        english: processed.english,
                        status: .translated
                    )
                    
                    logger.info("🔄 Updated sentence at index \(sentenceIndex) in memory, ID: \(sentences[sentenceIndex].id)")
                    
                    // Update the document
                    documentToUpdate.sentences = sentences
                    
                    // Update in store (use detached task only if navigating to avoid UI issues)
                    if shouldNavigate {
                        Task.detached { @MainActor in
                            do {
                                try await self.store.update(documentToUpdate)
                                self.logger.info("✅ Successfully saved sentence \(processed.index + 1)/\(chineseLinesToProcess.count) to database")
                            } catch {
                                self.logger.error("❌ Failed to update document in database: \(error)")
                            }
                        }
                    } else {
                        Task {
                            do {
                                try await self.store.update(documentToUpdate)
                                self.logger.info("✅ Successfully saved sentence \(processed.index + 1)/\(chineseLinesToProcess.count) to database (non-navigate)")
                            } catch {
                                self.logger.error("❌ Failed to update document in database (non-navigate): \(error)")
                            }
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
                            let originalSentence = sentences[sentenceIndex]
                            // Preserve the original ID and bbox
                            sentences[sentenceIndex] = Sentence(
                                id: originalSentence.id, // PRESERVE ORIGINAL ID!
                                text: processed.chinese,
                                rangeInImage: originalSentence.rangeInImage, // Keep the original bbox
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
    case noFramesExtracted
    case invalidVideo
    
    var errorDescription: String? {
        switch self {
        case .imageLoadFailed:
            return "Failed to load image"
        case .noChineseDetected:
            return "Unsnapzify-able!"
        case .noFramesExtracted:
            return "Failed to extract frames from video"
        case .invalidVideo:
            return "Invalid video file"
        }
    }
}
