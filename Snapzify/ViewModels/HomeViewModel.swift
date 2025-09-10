import Foundation
import SwiftUI
import UIKit
import Photos
import AVFoundation
import os.log

@MainActor
class HomeViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "HomeViewModel")
    private var documentCache: [UUID: Document] = [:]  // Cache full documents only when needed
    @Published var isProcessing = false
    @Published var isProcessingSharedImage = false
    @Published var isLoading = false
    @Published var showPhotoPicker = false
    @Published var errorMessage: String?
    @Published var processingProgress: String = ""
    @Published var activeProcessingTasks: [ProcessingTask] = []
    
    // Reverse Snapzify properties
    @Published var reverseSnapzifyText: String = ""
    @Published var isTranslating: Bool = false
    @Published var translationResult: String = ""
    
    // Chinese breakdown properties
    @Published var breakdownText: String = ""
    @Published var isBreakingDown: Bool = false
    @Published var breakdownResult: String = ""
    weak var appState: AppState?
    
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
    
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    private let chineseProcessingService: ChineseProcessingService = ServiceContainer.shared.chineseProcessingService
    private let streamingChineseProcessingService: StreamingChineseProcessingService = ServiceContainer.shared.streamingChineseProcessingService
    private lazy var englishToChineseService: EnglishToChineseTranslationService = {
        EnglishToChineseTranslationServiceImpl(configService: ServiceContainer.shared.configService)
    }()
    var onOpenSettings: () -> Void
    var onOpenDocument: (Document) -> Void
    var onProcessingProgress: ((Double) -> Void)?
    @AppStorage("selectedScript") private var selectedScript: String = ChineseScript.simplified.rawValue
    
    
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
                    status: .ocrOnly,
                    timestamp: appearances.first?.timestamp, // Keep first timestamp for compatibility
                    frameAppearances: appearances // Store all appearances
                ))
            }
            
            // Sort sentences by their first appearance timestamp to maintain chronological order
            // and by vertical position for sentences in the same frame
            allSentences.sort { sentence1, sentence2 in
                let time1 = sentence1.timestamp ?? 0
                let time2 = sentence2.timestamp ?? 0
                
                // If they appear in the same frame (within 0.1 seconds), sort by vertical position
                if abs(time1 - time2) < 0.1 {
                    let y1 = sentence1.rangeInImage?.minY ?? 0
                    let y2 = sentence2.rangeInImage?.minY ?? 0
                    return y1 < y2  // Top to bottom
                }
                
                return time1 < time2
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
            
            // Update UI and navigate to the document after everything is processed
            await MainActor.run {
                // No longer maintaining documents list
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
    
    func processQueuedImage(_ image: UIImage, source: DocumentSource = .shareExtension) async {
        do {
            _ = try await processImage(image, source: source, forQueue: true)
        } catch {
            logger.error("Failed to process queued image: \(error)")
        }
    }
    
    func processImageForQueue(_ image: UIImage, source: DocumentSource = .shareExtension) async throws -> Document {
        // Process image without navigation and without adding to queue documents
        let script = ChineseScript(rawValue: selectedScript) ?? .simplified
        
        // Report progress based on Chinese text processing
        let document = try await processImageCore(
            image,
            source: source,
            script: script,
            assetIdentifier: nil,
            shouldNavigate: false
        )
        
        // Report completion
        onProcessingProgress?(1.0)
        
        return document
    }
    
    func processVideoForQueue(_ videoURL: URL, source: DocumentSource = .imported) async throws -> Document {
        // Process video without navigation, similar to processPickedVideo but returning a Document
        let script = ChineseScript(rawValue: selectedScript) ?? .simplified
        
        // Extract frames from video
        let frames = try await extractFramesFromVideo(videoURL, frameInterval: 0.2)
        
        guard !frames.isEmpty else {
            throw ProcessingError.noFramesExtracted
        }
        
        // Process all frames for OCR
        var textAppearances: [String: [FrameAppearance]] = [:]
        let frameInterval = 0.2
        
        let maxConcurrentRequests = 25
        var processedCount = 0
        
        if frames.count <= maxConcurrentRequests {
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
                    
                    // Report progress
                    let progress = Double(processedCount) / Double(frames.count)
                    onProcessingProgress?(progress * 0.5) // OCR is 50% of the work
                }
                
                return allResults.sorted { $0.0 < $1.0 }
            }
            
            // Process OCR results
            for (index, ocrLines) in results {
                let frameTime = Double(index) * frameInterval
                for line in ocrLines {
                    let text = line.text
                    // Only include text that contains Chinese characters
                    if !text.isEmpty && containsChinese(text) {
                        let appearance = FrameAppearance(
                            timestamp: frameTime,
                            bbox: line.bbox
                        )
                        if textAppearances[text] != nil {
                            textAppearances[text]?.append(appearance)
                        } else {
                            textAppearances[text] = [appearance]
                        }
                    }
                }
            }
        } else {
            // Process in batches for larger videos
            for batchStart in stride(from: 0, to: frames.count, by: maxConcurrentRequests) {
                let batchEnd = min(batchStart + maxConcurrentRequests, frames.count)
                let batch = Array(frames[batchStart..<batchEnd])
                
                let results = try await withThrowingTaskGroup(of: (Int, [OCRLine]).self) { group in
                    for (localIndex, frame) in batch.enumerated() {
                        let globalIndex = batchStart + localIndex
                        group.addTask {
                            let ocrLines = try await self.ocrService.recognizeText(in: frame)
                            return (globalIndex, ocrLines)
                        }
                    }
                    
                    var batchResults: [(Int, [OCRLine])] = []
                    for try await result in group {
                        batchResults.append(result)
                        processedCount += 1
                        
                        // Report progress
                        let progress = Double(processedCount) / Double(frames.count)
                        onProcessingProgress?(progress * 0.5)
                    }
                    
                    return batchResults.sorted { $0.0 < $1.0 }
                }
                
                // Process OCR results for this batch
                for (index, ocrLines) in results {
                    let frameTime = Double(index) * frameInterval
                    for line in ocrLines {
                        let text = line.text
                        // Only include text that contains Chinese characters
                        if !text.isEmpty && containsChinese(text) {
                            let appearance = FrameAppearance(
                                timestamp: frameTime,
                                bbox: line.bbox
                            )
                            if textAppearances[text] != nil {
                                textAppearances[text]?.append(appearance)
                            } else {
                                textAppearances[text] = [appearance]
                            }
                        }
                    }
                }
            }
        }
        
        // Convert to sentences and sort by first appearance timestamp AND vertical position
        var allSentences: [Sentence] = []
        for (text, appearances) in textAppearances {
            allSentences.append(Sentence(
                text: text,
                frameAppearances: appearances
            ))
        }
        
        // Sort sentences by their first appearance timestamp, then by vertical position (top to bottom)
        allSentences.sort { sentence1, sentence2 in
            let time1 = sentence1.frameAppearances?.first?.timestamp ?? 0
            let time2 = sentence2.frameAppearances?.first?.timestamp ?? 0
            
            // If they appear in the same frame (within 0.1 seconds), sort by vertical position
            if abs(time1 - time2) < 0.1 {
                let y1 = sentence1.frameAppearances?.first?.bbox.minY ?? 0
                let y2 = sentence2.frameAppearances?.first?.bbox.minY ?? 0
                return y1 < y2  // Top to bottom
            }
            
            return time1 < time2
        }
        
        guard !allSentences.isEmpty else {
            throw ProcessingError.noChineseDetected
        }
        
        // Report 75% progress after processing
        onProcessingProgress?(0.75)
        
        // Create document
        let representativeImage = frames.first!
        let videoData = try Data(contentsOf: videoURL)
        let documentId = UUID()
        
        let savedVideoURL = try await MainActor.run {
            try MediaStorageService.shared.saveMedia(videoData, id: documentId, isVideo: true)
        }
        
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
            source: source,
            script: script,
            sentences: allSentences,
            mediaURL: savedVideoURL,
            thumbnailURL: thumbnailURL,
            isVideo: true
        )
        
        try await store.save(document)
        
        // Report completion
        onProcessingProgress?(1.0)
        
        return document
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
    
    private func processImage(_ image: UIImage, source: DocumentSource, assetIdentifier: String? = nil, forQueue: Bool = false) async throws -> Document {
        let script = ChineseScript(rawValue: selectedScript) ?? .simplified
        let document = try await processImageCore(
            image,
            source: source,
            script: script,
            assetIdentifier: assetIdentifier,
            shouldNavigate: !forQueue  // Don't navigate immediately if processing for queue
        )
        
        // If processing for queue, add to queue documents and navigate if it's the first
        if forQueue {
            await MainActor.run {
                appState?.queueDocuments.append(document)
                
                // If this is the first queue item, navigate to it
                if appState?.queueDocuments.count == 1 {
                    appState?.currentQueueIndex = 0
                    appState?.currentQueueDocument = document
                    // Dismiss the processing screen
                    appState?.isProcessingQueue = false
                    // Navigate to the document
                    onOpenDocument(document)
                }
            }
        }
        
        return document
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
                let _ = components[1].trimmingCharacters(in: .whitespacesAndNewlines) // pinyin - no longer used
                let english = components[2].trimmingCharacters(in: .whitespacesAndNewlines)
                
                if containsChinese(chinese) {
                    let normalizedChinese = script == .simplified ?
                        scriptConversionService.toSimplified(chinese) :
                        scriptConversionService.toTraditional(chinese)
                    
                    sentences.append(Sentence(
                        text: normalizedChinese,
                        rangeInImage: line.bbox, // Use the bbox from OCR
                        tokens: [],
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
            // No longer maintaining documents list
            
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
                    
                    logger.info("🔄 Received processed sentence \(processed.index): chinese='\(processed.chinese)'")
                    
                    // Update progress (Note: This callback is not async)
                    Task { @MainActor in
                        self.processingProgress = "Translating... (\(processed.index + 1)/\(chineseLinesToProcess.count))"
                        
                        if let index = self.activeProcessingTasks.firstIndex(where: { $0.id == taskId }) {
                            self.activeProcessingTasks[index].progress = "Translating... (\(processed.index + 1)/\(chineseLinesToProcess.count))"
                        }
                        
                        // Report progress to callback
                        let progress = Double(processed.index + 1) / Double(chineseLinesToProcess.count)
                        self.onProcessingProgress?(progress)
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
    
    // MARK: - Reverse Snapzify
    
    func performBreakdown() async {
        guard !breakdownText.isEmpty else {
            print("DEBUG: Cannot perform breakdown - no text")
            return
        }
        guard englishToChineseService.isConfigured() else {
            print("DEBUG: Service not configured")
            await MainActor.run {
                errorMessage = "OpenAI API key not configured. Please add it in Settings."
            }
            return
        }
        
        // Save the query to show as header
        let queryText = breakdownText
        UserDefaults.standard.set(queryText, forKey: "currentBreakdownQuery")
        
        print("DEBUG: Starting breakdown for: \(queryText)")
        await MainActor.run {
            isBreakingDown = true
            breakdownResult = ""
            // Clear the text field after submit
            breakdownText = ""
        }
        
        do {
            let stream = englishToChineseService.streamBreakdown(queryText)
            
            for try await chunk in stream {
                await MainActor.run {
                    self.breakdownResult += chunk
                }
            }
            
            await MainActor.run {
                self.isBreakingDown = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Breakdown failed: \(error.localizedDescription)"
                self.isBreakingDown = false
            }
        }
    }
    
    func performReverseSnapzify() async {
        guard !reverseSnapzifyText.isEmpty else { 
            print("DEBUG: Cannot perform reverse snapzify - no text")
            return 
        }
        guard englishToChineseService.isConfigured() else {
            print("DEBUG: Service not configured")
            await MainActor.run {
                errorMessage = "OpenAI API key not configured. Please add it in Settings."
            }
            return
        }
        
        // Save the query to show as header
        let queryText = reverseSnapzifyText
        UserDefaults.standard.set(queryText, forKey: "currentTranslationQuery")
        
        print("DEBUG: Starting translation for: \(queryText)")
        await MainActor.run {
            isTranslating = true
            translationResult = ""
            // Clear the text field after submit
            reverseSnapzifyText = ""
        }
        
        do {
            let stream = englishToChineseService.streamTranslate(queryText)
            
            print("DEBUG: Starting to read stream")
            for try await chunk in stream {
                print("DEBUG: Received chunk: \(chunk)")
                await MainActor.run {
                    self.translationResult += chunk
                    print("DEBUG: Total result so far: \(self.translationResult)")
                }
            }
            
            print("DEBUG: Stream finished")
            await MainActor.run {
                self.isTranslating = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Translation failed: \(error.localizedDescription)"
                self.isTranslating = false
            }
        }
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
