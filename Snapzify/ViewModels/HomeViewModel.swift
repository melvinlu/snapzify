import Foundation
import SwiftUI
import Photos
import AVFoundation
import os.log

@MainActor
class HomeViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "HomeViewModel")
    @Published var documents: [DocumentMetadata] = []
    @Published var savedDocuments: [DocumentMetadata] = []
    private var documentCache: [UUID: Document] = [:]  // Cache full documents only when needed
    @Published var shouldSuggestLatest = false
    @Published var latestInfo: LatestScreenshotInfo?
    @Published var isProcessing = false
    @Published var isProcessingSharedImage = false
    @Published var isLoading = true
    @Published var showPhotoPicker = false
    @Published var errorMessage: String?
    @Published var processingProgress: String = ""
    @Published var activeProcessingTasks: [ProcessingTask] = []
    
    struct ProcessingTask: Identifiable {
        let id: UUID
        var name: String
        var progress: String
        var progressValue: Double // 0.0 to 1.0
        var totalFrames: Int
        var processedFrames: Int
        var type: ProcessingType
        var thumbnail: UIImage?
        
        enum ProcessingType {
            case image
            case video
            case shared
        }
    }
    
    @Published private(set) var hasLoadedDocuments = false
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
            // Load lightweight metadata in parallel
            async let recentMeta = store.fetchRecentMetadata(limit: 10)
            async let savedMeta = store.fetchSavedMetadata()
            
            // Only check for screenshot, don't wait for it
            Task { await checkForLatestScreenshot() }
            
            // Wait for metadata to load
            documents = try await recentMeta
            savedDocuments = try await savedMeta
            
            hasLoadedDocuments = true
        } catch {
            print("Failed to load documents: \(error)")
        }
        isLoading = false
    }
    
    func refreshDocuments() async {
        // Force refresh documents WITHOUT showing loading state
        do {
            documents = try await store.fetchRecentMetadata(limit: 10)
            savedDocuments = try await store.fetchSavedMetadata()
            Task { await checkForLatestScreenshot() }
        } catch {
            print("Failed to load documents: \(error)")
        }
    }
    
    func refreshSavedDocuments() async {
        // Refresh only saved documents metadata (lightweight)
        do {
            savedDocuments = try await store.fetchSavedMetadata()
            // Only update recent if needed
            if documents.isEmpty {
                documents = try await store.fetchRecentMetadata(limit: 10)
            }
        } catch {
            print("Failed to refresh saved documents: \(error)")
        }
    }
    
    func updateDocumentSavedStatus(_ updatedDocument: Document) {
        // Update metadata arrays with new metadata
        let updatedMetadata = DocumentMetadata(from: updatedDocument)
        
        // Update in documents array - remove and re-insert to trigger SwiftUI update
        if let index = documents.firstIndex(where: { $0.id == updatedDocument.id }) {
            documents.remove(at: index)
            documents.insert(updatedMetadata, at: index)
        }
        
        // Update saved documents array
        if updatedDocument.isSaved {
            // Add to saved if not already there
            if !savedDocuments.contains(where: { $0.id == updatedDocument.id }) {
                savedDocuments.append(updatedMetadata)
                savedDocuments.sort { $0.createdAt > $1.createdAt }
            } else {
                // Update existing - remove and re-insert to trigger SwiftUI update
                if let index = savedDocuments.firstIndex(where: { $0.id == updatedDocument.id }) {
                    savedDocuments.remove(at: index)
                    savedDocuments.insert(updatedMetadata, at: index)
                }
            }
        } else {
            // Remove from saved
            savedDocuments.removeAll { $0.id == updatedDocument.id }
        }
        
        // Update cache if present
        documentCache[updatedDocument.id] = updatedDocument
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
            // Create processing task immediately
            let taskId = UUID()
            
            await MainActor.run {
                let task = ProcessingTask(
                    id: taskId,
                    name: "Photo",
                    progress: "Preparing",
                    progressValue: 0.0,
                    totalFrames: 0,
                    processedFrames: 0,
                    type: .image,
                    thumbnail: nil
                )
                self.activeProcessingTasks.append(task)
                isProcessing = true
            }
            
            do {
                let image = try await loadImage(from: info.asset)
                
                // Create and update thumbnail
                let thumbnailSize = CGSize(width: 60, height: 60)
                await MainActor.run {
                    UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                    image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                    let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                        self.activeProcessingTasks[index].thumbnail = thumbnailImage
                    }
                }
                
                // Add 60-second timeout to image processing
                let script = ChineseScript(rawValue: selectedScript) ?? .simplified
                _ = try await withTimeout(seconds: 60) {
                    try await self.processImageCore(
                        image,
                        source: .photos,
                        script: script,
                        assetIdentifier: info.asset.localIdentifier,
                        shouldNavigate: true,
                        existingTaskId: taskId
                    )
                }
                
                // Document is already saved in processImage
                shouldSuggestLatest = false
                
                // Remove task after successful completion
                await MainActor.run {
                    self.activeProcessingTasks.removeAll { $0.id == taskId }
                }
            } catch {
                print("Failed to snapzify screenshot: \(error)")
                await MainActor.run {
                    self.activeProcessingTasks.removeAll { $0.id == taskId }
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
    
    func processPickedImageWithTask(_ image: UIImage, taskId: UUID, checkVisibility: @escaping () -> Bool) async {
        // Update existing task with thumbnail
        let thumbnailSize = CGSize(width: 60, height: 60)
        let thumbnail = await MainActor.run {
            UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
            let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return thumbnailImage
        }
        
        await MainActor.run {
            if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                self.activeProcessingTasks[index].thumbnail = thumbnail
                self.activeProcessingTasks[index].type = .image
            }
        }
        
        do {
            logger.info("Starting image snapzifying")
            
            // Add 60-second timeout to image processing
            _ = try await withTimeout(seconds: 60) {
                try await self.processImageCore(image, source: .imported, script: ChineseScript(rawValue: self.selectedScript) ?? .simplified, assetIdentifier: nil, shouldNavigate: checkVisibility(), existingTaskId: taskId)
            }
            
            logger.info("Snapzifying completed")
            
            // Remove task after successful completion
            await MainActor.run {
                self.activeProcessingTasks.removeAll { $0.id == taskId }
            }
        } catch {
            logger.error("Failed to snapzify image: \(error.localizedDescription)")
            await MainActor.run {
                self.activeProcessingTasks.removeAll { $0.id == taskId }
                self.isProcessing = false
                if error is TimeoutError {
                    self.errorMessage = "Snapzifying timed out. Please try again with a simpler image."
                } else if let processingError = error as? ProcessingError {
                    self.errorMessage = processingError.errorDescription ?? "Failed to process image"
                } else {
                    self.errorMessage = "Failed to process image: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func processPickedImage(_ image: UIImage) {
        Task {
            // Create processing task immediately
            let taskId = UUID()
            
            // Create thumbnail
            let thumbnailSize = CGSize(width: 60, height: 60)
            let thumbnail = await MainActor.run {
                UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return thumbnailImage
            }
            
            await MainActor.run {
                let task = ProcessingTask(
                    id: taskId,
                    name: "Image",
                    progress: "Preparing",
                    progressValue: 0.0,
                    totalFrames: 0,
                    processedFrames: 0,
                    type: .image,
                    thumbnail: thumbnail
                )
                self.activeProcessingTasks.append(task)
                isProcessing = true
                errorMessage = nil
            }
            
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
                
                // Remove task after successful completion
                await MainActor.run {
                    self.activeProcessingTasks.removeAll { $0.id == taskId }
                }
            } catch {
                logger.error("Failed to snapzify picked image: \(error.localizedDescription)")
                await MainActor.run {
                    self.activeProcessingTasks.removeAll { $0.id == taskId }
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
        // Create a task ID and delegate to the new method
        let taskId = UUID()
        await MainActor.run {
            let task = ProcessingTask(
                id: taskId,
                name: "Video",
                progress: "Preparing",
                progressValue: 0.0,
                totalFrames: 0,
                processedFrames: 0,
                type: .video,
                thumbnail: nil
            )
            self.activeProcessingTasks.append(task)
            self.isProcessing = true
        }
        await processPickedVideoWithTask(videoURL, taskId: taskId, checkVisibility: { true })
    }
    
    func processPickedVideoWithTask(_ videoURL: URL, taskId: UUID, checkVisibility: @escaping () -> Bool) async {
        // The task is already created with "Uploading" status
        await MainActor.run {
            errorMessage = nil
        }
        
        do {
            logger.info("Starting video processing from URL: \(videoURL)")
            
            // Task already shows "Preparing" - no need to update
            
            // Extract frames from video
            // Extract frames every 0.2 seconds for real-time tappability
            let frames = try await extractFramesFromVideo(videoURL, frameInterval: 0.2)
            
            guard !frames.isEmpty else {
                await MainActor.run {
                    self.activeProcessingTasks.removeAll { $0.id == taskId }
                }
                throw ProcessingError.noFramesExtracted
            }
            
            logger.info("Extracted \(frames.count) frames from video")
            
            // Create thumbnail from first frame and update task
            if let firstFrame = frames.first {
                let thumbnailSize = CGSize(width: 60, height: 60)
                await MainActor.run {
                    UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                    firstFrame.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                    let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    // Update task with thumbnail and frame count
                    if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                        self.activeProcessingTasks[index].thumbnail = thumbnailImage
                        self.activeProcessingTasks[index].totalFrames = frames.count
                        self.activeProcessingTasks[index].processedFrames = 0
                        self.activeProcessingTasks[index].progressValue = 0.0
                        self.activeProcessingTasks[index].progress = "0%"
                    }
                }
            }
            
            // Process all frames concurrently for OCR
            // Dictionary to track all appearances of each unique text
            var textAppearances: [String: [FrameAppearance]] = [:]
            let frameInterval = 0.2 // seconds between frames (must match extraction interval)
            
            logger.info("Starting ULTRA-FAST concurrent OCR processing for \(frames.count) frames")
            
            var processedCount = 0
            
            // Process ALL frames concurrently with smart batching
            // Google Cloud Vision allows up to 30 requests per second, but we can queue more
            let maxConcurrentRequests = 25 // Process up to 25 frames at once
            
            // Process all frames in one go if under the limit, otherwise use batches
            if frames.count <= maxConcurrentRequests {
                // Process ALL frames at once if we're under the limit
                logger.info("Processing all \(frames.count) frames in a single concurrent batch!")
                
                let results = try await withThrowingTaskGroup(of: (Int, [OCRLine]).self) { group in
                    for (index, frame) in frames.enumerated() {
                        group.addTask {
                            let ocrLines = try await self.ocrService.recognizeText(in: frame)
                            return (index, ocrLines)
                        }
                    }
                    
                    var allResults: [(Int, [OCRLine])] = []
                    for try await result in group {
                        allResults.append(result)
                        processedCount += 1
                        
                        // Update progress percentage
                        let percentage = Int((Double(processedCount) / Double(frames.count)) * 100)
                        await MainActor.run {
                            if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                                self.activeProcessingTasks[index].processedFrames = processedCount
                                self.activeProcessingTasks[index].progressValue = Double(processedCount) / Double(frames.count)
                                self.activeProcessingTasks[index].progress = "\(percentage)%"
                            }
                        }
                    }
                    return allResults
                }
                
                // Process all results
                for (frameIndex, ocrLines) in results {
                    let timestamp = Double(frameIndex) * frameInterval
                    
                    for line in ocrLines {
                        if containsChinese(line.text) {
                            let normalizedText = ChineseScript(rawValue: selectedScript) == .simplified ?
                                scriptConversionService.toSimplified(line.text) :
                                scriptConversionService.toTraditional(line.text)
                            
                            let appearance = FrameAppearance(timestamp: timestamp, bbox: line.bbox)
                            
                            if textAppearances[normalizedText] == nil {
                                textAppearances[normalizedText] = []
                            }
                            textAppearances[normalizedText]?.append(appearance)
                        }
                    }
                }
            } else {
                // For larger videos, process in larger concurrent batches
                logger.info("Processing \(frames.count) frames in batches of \(maxConcurrentRequests)")
                
                for batchStart in stride(from: 0, to: frames.count, by: maxConcurrentRequests) {
                    let batchEnd = min(batchStart + maxConcurrentRequests, frames.count)
                    let batch = Array(frames[batchStart..<batchEnd])
                    let batchIndices = Array(batchStart..<batchEnd)
                    
                    logger.debug("Processing mega-batch: frames \(batchStart + 1)-\(batchEnd)/\(frames.count)")
                    
                    // Process this batch with maximum concurrency
                    let batchResults = try await withThrowingTaskGroup(of: (Int, [OCRLine]).self) { group in
                        for (localIndex, frame) in batch.enumerated() {
                            let frameIndex = batchIndices[localIndex]
                            group.addTask(priority: .high) { // High priority for faster processing
                                let ocrLines = try await self.ocrService.recognizeText(in: frame)
                                return (frameIndex, ocrLines)
                            }
                        }
                        
                        var results: [(Int, [OCRLine])] = []
                        for try await result in group {
                            results.append(result)
                            processedCount += 1
                            
                            // Update progress percentage
                            let percentage = Int((Double(processedCount) / Double(frames.count)) * 100)
                            await MainActor.run {
                                if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                                    self.activeProcessingTasks[index].processedFrames = processedCount
                                    self.activeProcessingTasks[index].progressValue = Double(processedCount) / Double(frames.count)
                                    self.activeProcessingTasks[index].progress = "\(percentage)%"
                                }
                            }
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
                                
                                let appearance = FrameAppearance(timestamp: timestamp, bbox: line.bbox)
                                
                                if textAppearances[normalizedText] == nil {
                                    textAppearances[normalizedText] = []
                                }
                                textAppearances[normalizedText]?.append(appearance)
                            }
                        }
                    }
                    
                    // NO DELAY between batches - process as fast as possible!
                    // The API will handle rate limiting if needed
                }
            }
            
            logger.info("Completed ULTRA-FAST concurrent OCR processing for all frames")
            
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
            let documentId = UUID()
            let savedVideoURL = try await MainActor.run {
                try MediaStorageService.shared.saveMedia(videoData, id: documentId, isVideo: true)
            }
            
            // Create thumbnail
            let thumbnailURL: URL? = try? await MainActor.run {
                let thumbnailSize = CGSize(width: 120, height: 120)
                let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
                let thumbnail = renderer.image { context in
                    representativeImage.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                }
                return try MediaStorageService.shared.saveThumbnail(thumbnail, id: documentId)
            }
            
            let document = Document(
                id: documentId,
                source: .imported,
                script: script,
                sentences: allSentences,
                mediaURL: savedVideoURL,
                thumbnailURL: thumbnailURL,
                isVideo: true
            )
            
            try await store.save(document)
            let savedDocument = document
            
            // Navigate to the document after everything is processed
            await MainActor.run {
                self.documents.insert(DocumentMetadata(from: savedDocument), at: 0)
                self.isProcessing = false
                // Remove the processing task
                self.activeProcessingTasks.removeAll { $0.id == taskId }
                
                // Check visibility at completion time - if we're on home page, navigate
                let shouldNavigate = checkVisibility()
                if shouldNavigate {
                    self.onOpenDocument(savedDocument)
                }
            }
            
            // Clean up temporary video file
            try? FileManager.default.removeItem(at: videoURL)
            
        } catch {
            logger.error("Failed to process video: \(error.localizedDescription)")
            await MainActor.run {
                // Remove the processing task on error
                self.activeProcessingTasks.removeAll { $0.id == taskId }
                // Clear isProcessing if no more tasks remain
                if self.activeProcessingTasks.isEmpty {
                    isProcessing = false
                }
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
    
    func open(_ metadata: DocumentMetadata) {
        Task {
            // Check cache first
            if let cached = documentCache[metadata.id] {
                await MainActor.run {
                    onOpenDocument(cached)
                }
            } else {
                // Fetch full document only when needed
                if let document = try? await store.fetch(id: metadata.id) {
                    documentCache[metadata.id] = document
                    await MainActor.run {
                        onOpenDocument(document)
                    }
                }
            }
        }
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
        shouldNavigate: Bool,
        existingTaskId: UUID? = nil
    ) async throws -> Document {
        // Use existing task ID if provided, otherwise create new one
        let taskId = existingTaskId ?? UUID()
        let taskName = source == .shareExtension ? "Shared Image" : 
                       source == .photos ? "Photo" : "Image"
        
        // Only create a new task if one doesn't exist with this ID
        if existingTaskId == nil {
            // Create a small thumbnail
            let thumbnailSize = CGSize(width: 60, height: 60)
            let thumbnail = await MainActor.run {
                UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 0.0)
                image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return thumbnailImage
            }
            
            await MainActor.run {
                let task = ProcessingTask(
                    id: taskId,
                    name: taskName,
                    progress: "Processing",
                    progressValue: 0.0,
                    totalFrames: 0,
                    processedFrames: 0,
                    type: source == .shareExtension ? .shared : .image,
                    thumbnail: thumbnail
                )
                self.activeProcessingTasks.append(task)
            }
        }
        
        // Helper to update task progress
        @Sendable func updateTaskProgress(_ progress: String) async {
            await MainActor.run {
                if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                    self.activeProcessingTasks[index].progress = progress
                }
            }
        }
        
        // Helper to remove task when done
        @Sendable func removeTask() async {
            await MainActor.run {
                self.activeProcessingTasks.removeAll { $0.id == taskId }
            }
        }
        
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
            await removeTask()
            throw ProcessingError.noChineseDetected
        }
        
        // No need to update progress for images - they process quickly
        
        // Create document with initial sentences (including placeholders)
        logger.info("Created document with \(sentences.count) sentences")
        
        // Save image to file
        let documentId = UUID()
        guard let imageData = image.pngData() else {
            throw ProcessingError.failedToSaveImage
        }
        let imageURL = try await MainActor.run {
            try MediaStorageService.shared.saveMedia(imageData, id: documentId, isVideo: false)
        }
        
        // Create thumbnail
        let thumbnailURL: URL? = try? await MainActor.run {
            let thumbnailSize = CGSize(width: 120, height: 120)
            let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
            let thumbnail = renderer.image { context in
                image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
            }
            return try MediaStorageService.shared.saveThumbnail(thumbnail, id: documentId)
        }
        
        let document = Document(
            id: documentId,
            source: source,
            script: script,
            sentences: sentences,
            mediaURL: imageURL,
            thumbnailURL: thumbnailURL,
            isVideo: false,
            assetIdentifier: assetIdentifier
        )
        
        // Save document
        try await store.save(document)
        let savedDocument = document
        
        // Handle navigation and UI updates
        await MainActor.run {
            // Add the document to the local documents array immediately
            self.documents.insert(DocumentMetadata(from: savedDocument), at: 0)
            
            // Navigation decision - check if we're still on home page at completion time
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
            
            // Remove the task when navigation happens
            if shouldNavigate {
                self.activeProcessingTasks.removeAll { $0.id == taskId }
            }
        }
        
        // Second pass: stream process Chinese lines with concurrent requests
        if !chineseLinesToProcess.isEmpty {
            logger.info("Stream processing \(chineseLinesToProcess.count) Chinese lines")
            
            // Update progress
            await MainActor.run {
                self.processingProgress = "Translating \(chineseLinesToProcess.count) sentences..."
            }
            
            do {
                // Store a reference to the document for updates
                var documentToUpdate = savedDocument
                
                try await streamingChineseProcessingService.processStreamingBatch(
                    chineseLinesToProcess,
                    script: script
                ) { [weak self] processed in
                    guard let self = self else { return }
                    
                    logger.info("🔄 Received processed sentence \(processed.index): english='\(processed.english)', pinyin=\(processed.pinyin)")
                    
                    // Update progress (Note: This callback is not async)
                    Task { @MainActor in
                        self.processingProgress = "Translating... (\(processed.index + 1)/\(chineseLinesToProcess.count))"
                        
                        if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                            self.activeProcessingTasks[index].progress = "Translating... (\(processed.index + 1)/\(chineseLinesToProcess.count))"
                        }
                    }
                    
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
        
        // Clean up task if not already removed (e.g., when not navigating)
        await removeTask()
        
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
    case failedToSaveImage
    case failedToReadVideo
    
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
        case .failedToSaveImage:
            return "Failed to save image"
        case .failedToReadVideo:
            return "Failed to read video file"
        }
    }
}
