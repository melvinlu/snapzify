import Foundation
import UIKit
import AVFoundation
import Photos
import os.log

// MARK: - Media Input Types
enum MediaInput {
    case image(UIImage)
    case video(URL)
    case photoAsset(PHAsset)
    case data(Data, type: MediaType)
    
    enum MediaType {
        case image
        case video
    }
}

// MARK: - Processing Configuration
struct ProcessingConfiguration {
    let script: ChineseScript
    let frameInterval: TimeInterval
    let maxFrames: Int
    let compressionQuality: CGFloat
    let generateThumbnail: Bool
    let generateAudio: Bool
    let autoTranslate: Bool
    
    static var `default`: ProcessingConfiguration {
        ProcessingConfiguration(
            script: .simplified,
            frameInterval: Constants.Media.frameExtractionInterval,
            maxFrames: Constants.Media.maxVideoFramesToProcess,
            compressionQuality: Constants.Media.imageCompressionQuality,
            generateThumbnail: true,
            generateAudio: false,
            autoTranslate: true
        )
    }
}

// MARK: - Processing Result
struct ProcessingResult {
    let document: Document
    let thumbnails: [UIImage]
    let processingTime: TimeInterval
    let frameCount: Int
    let errors: [Error]
}

// MARK: - Media Processor Protocol
protocol MediaProcessor {
    func process(_ input: MediaInput, configuration: ProcessingConfiguration) async throws -> ProcessingResult
    func cancelProcessing()
}

// MARK: - Unified Media Processor
/// Consolidated processing pipeline for all media types
@MainActor
final class UnifiedMediaProcessor: MediaProcessor {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "UnifiedMediaProcessor")
    
    // Dependencies
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    private let chineseProcessingService: ChineseProcessingService
    private let streamingChineseProcessingService: StreamingChineseProcessingService
    private let mediaStorage: MediaStorageService
    private let documentStore: DocumentStore
    private let errorManager: ErrorRecoveryManager
    
    // Processing state
    private var currentTask: Task<ProcessingResult, Error>?
    private var isCancelled = false
    
    // Progress tracking
    var onProgress: ((Double, String) -> Void)?
    
    init(
        ocrService: OCRService,
        scriptConversionService: ScriptConversionService,
        chineseProcessingService: ChineseProcessingService,
        streamingChineseProcessingService: StreamingChineseProcessingService,
        mediaStorage: MediaStorageService,
        documentStore: DocumentStore
    ) {
        self.ocrService = ocrService
        self.scriptConversionService = scriptConversionService
        self.chineseProcessingService = chineseProcessingService
        self.streamingChineseProcessingService = streamingChineseProcessingService
        self.mediaStorage = mediaStorage
        self.documentStore = documentStore
        self.errorManager = ErrorRecoveryManager.shared
    }
    
    // MARK: - Public Methods
    
    func process(_ input: MediaInput, configuration: ProcessingConfiguration) async throws -> ProcessingResult {
        logger.info("Starting unified media processing")
        let startTime = Date()
        isCancelled = false
        
        // Cancel any existing task
        currentTask?.cancel()
        
        // Create new processing task
        let task = Task<ProcessingResult, Error> {
            try await processInternal(input, configuration: configuration, startTime: startTime)
        }
        
        currentTask = task
        
        do {
            let result = try await task.value
            logger.info("Processing completed successfully - frames: \(result.frameCount), time: \(result.processingTime)s")
            return result
        } catch {
            logger.error("Processing failed: \(error)")
            errorManager.handle(error, context: "Media processing")
            throw error
        }
    }
    
    func cancelProcessing() {
        logger.info("Cancelling processing")
        isCancelled = true
        currentTask?.cancel()
    }
    
    // MARK: - Internal Processing
    
    private func processInternal(_ input: MediaInput, configuration: ProcessingConfiguration, startTime: Date) async throws -> ProcessingResult {
        var frames: [UIImage] = []
        var errors: [Error] = []
        
        // Extract frames based on input type
        switch input {
        case .image(let image):
            frames = [image]
            updateProgress(0.2, "Processing image")
            
        case .video(let url):
            frames = try await extractVideoFrames(from: url, configuration: configuration)
            
        case .photoAsset(let asset):
            frames = try await extractFramesFromAsset(asset, configuration: configuration)
            
        case .data(let data, let type):
            frames = try await extractFramesFromData(data, type: type, configuration: configuration)
        }
        
        guard !frames.isEmpty else {
            throw MediaProcessingError.processingFailed("No frames extracted")
        }
        
        // Process frames through OCR pipeline
        updateProgress(0.4, "Extracting text from \(frames.count) frame(s)")
        let ocrResults = try await processFramesWithOCR(frames, configuration: configuration)
        
        // Merge and deduplicate results
        updateProgress(0.6, "Merging results")
        let mergedSentences = mergeOCRResults(ocrResults)
        
        // Process Chinese text
        updateProgress(0.8, "Processing Chinese text")
        let processedSentences = try await processChineseText(mergedSentences, configuration: configuration)
        
        // Generate thumbnail
        let thumbnail = generateThumbnail(from: frames.first!)
        
        // Save media and create document
        updateProgress(0.9, "Saving document")
        let document = try await createDocument(
            sentences: processedSentences,
            thumbnail: thumbnail,
            frames: frames,
            configuration: configuration
        )
        
        // Calculate processing time
        let processingTime = Date().timeIntervalSince(startTime)
        
        updateProgress(1.0, "Complete")
        
        return ProcessingResult(
            document: document,
            thumbnails: [thumbnail].compactMap { $0 },
            processingTime: processingTime,
            frameCount: frames.count,
            errors: errors
        )
    }
    
    // MARK: - Frame Extraction
    
    private func extractVideoFrames(from url: URL, configuration: ProcessingConfiguration) async throws -> [UIImage] {
        updateProgress(0.1, "Extracting video frames")
        
        let asset = AVAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaProcessingError.invalidFormat("No video track found")
        }
        
        let duration = try await asset.load(.duration)
        let frameInterval = configuration.frameInterval
        let totalFrames = min(
            Int(duration.seconds / frameInterval),
            configuration.maxFrames
        )
        
        var frames: [UIImage] = []
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        
        for i in 0..<totalFrames {
            if isCancelled { throw MediaProcessingError.cancelled }
            
            let time = CMTime(seconds: Double(i) * frameInterval, preferredTimescale: 600)
            
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let image = UIImage(cgImage: cgImage)
                frames.append(image)
                
                let progress = 0.1 + (0.3 * Double(i) / Double(totalFrames))
                updateProgress(progress, "Frame \(i + 1)/\(totalFrames)")
            } catch {
                logger.warning("Failed to extract frame at \(time.seconds): \(error)")
                // Continue with other frames
            }
        }
        
        return frames
    }
    
    private func extractFramesFromAsset(_ asset: PHAsset, configuration: ProcessingConfiguration) async throws -> [UIImage] {
        updateProgress(0.1, "Loading from photo library")
        
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let image = image {
                    continuation.resume(returning: [image])
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func extractFramesFromData(_ data: Data, type: MediaInput.MediaType, configuration: ProcessingConfiguration) async throws -> [UIImage] {
        switch type {
        case .image:
            guard let image = UIImage(data: data) else {
                throw MediaProcessingError.invalidFormat("Invalid image data")
            }
            return [image]
            
        case .video:
            // Save to temporary file and process
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return try await extractVideoFrames(from: tempURL, configuration: configuration)
        }
    }
    
    // MARK: - OCR Processing
    
    private func processFramesWithOCR(_ frames: [UIImage], configuration: ProcessingConfiguration) async throws -> [OCRResult] {
        var results: [OCRResult] = []
        
        for (index, frame) in frames.enumerated() {
            if isCancelled { throw MediaProcessingError.cancelled }
            
            let progress = 0.4 + (0.2 * Double(index) / Double(frames.count))
            updateProgress(progress, "OCR frame \(index + 1)/\(frames.count)")
            
            do {
                let result = try await ocrService.recognizeText(in: frame)
                results.append(result)
            } catch {
                logger.warning("OCR failed for frame \(index): \(error)")
                // Continue with other frames
            }
        }
        
        return results
    }
    
    // MARK: - Result Merging
    
    private func mergeOCRResults(_ results: [OCRResult]) -> [Sentence] {
        var uniqueSentences: [String: Sentence] = [:]
        var sentenceOrder: [String] = []
        
        for result in results {
            for observation in result.observations {
                let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Skip empty or very short text
                guard text.count >= Constants.TextProcessing.minSentenceLength else { continue }
                
                // Use text as key for deduplication
                if uniqueSentences[text] == nil {
                    let sentence = Sentence(
                        text: text,
                        boundingBox: observation.boundingBox,
                        pinyin: [],
                        translation: "",
                        status: .pending
                    )
                    uniqueSentences[text] = sentence
                    sentenceOrder.append(text)
                }
            }
        }
        
        // Return sentences in order they were found
        return sentenceOrder.compactMap { uniqueSentences[$0] }
    }
    
    // MARK: - Chinese Processing
    
    private func processChineseText(_ sentences: [Sentence], configuration: ProcessingConfiguration) async throws -> [Sentence] {
        guard !sentences.isEmpty else { return [] }
        
        var processedSentences = sentences
        
        // Convert script if needed
        if configuration.script == .traditional {
            for i in 0..<processedSentences.count {
                if let converted = try? scriptConversionService.convert(
                    processedSentences[i].text,
                    to: .traditional
                ) {
                    processedSentences[i].text = converted
                }
            }
        }
        
        // Process with Chinese service if auto-translate is enabled
        if configuration.autoTranslate {
            let texts = processedSentences.map { $0.text }
            
            do {
                let results = try await chineseProcessingService.processBatch(texts, script: configuration.script)
                
                for (index, result) in results.enumerated() where index < processedSentences.count {
                    processedSentences[index].pinyin = result.pinyin.components(separatedBy: " ")
                    processedSentences[index].translation = result.translation
                    processedSentences[index].status = .translated
                }
            } catch {
                logger.warning("Chinese processing failed: \(error)")
                // Continue without translations
            }
        }
        
        return processedSentences
    }
    
    // MARK: - Document Creation
    
    private func createDocument(
        sentences: [Sentence],
        thumbnail: UIImage?,
        frames: [UIImage],
        configuration: ProcessingConfiguration
    ) async throws -> Document {
        let documentId = UUID()
        
        // Save media files
        let mediaURL: URL?
        let thumbnailURL: URL?
        
        if frames.count == 1, let image = frames.first {
            // Single image
            mediaURL = try await mediaStorage.saveImage(image, documentId: documentId)
        } else {
            // Multiple frames - save as video or image sequence
            mediaURL = try await mediaStorage.saveImage(frames.first!, documentId: documentId)
        }
        
        if let thumbnail = thumbnail {
            thumbnailURL = try await mediaStorage.saveThumbnail(thumbnail, documentId: documentId)
        } else {
            thumbnailURL = nil
        }
        
        // Create document
        let document = Document(
            id: documentId,
            createdDate: Date(),
            modifiedDate: Date(),
            sentences: sentences,
            customName: nil,
            isSaved: false,
            mediaURL: mediaURL,
            thumbnailURL: thumbnailURL,
            script: configuration.script
        )
        
        return document
    }
    
    // MARK: - Helpers
    
    private func generateThumbnail(from image: UIImage) -> UIImage? {
        let size = Constants.Media.thumbnailSize
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    private func updateProgress(_ value: Double, _ message: String) {
        logger.debug("Progress: \(value) - \(message)")
        onProgress?(value, message)
    }
}

// MARK: - Processing Pipeline Manager
/// Manages multiple processing tasks with queue and priority
@MainActor
final class ProcessingPipelineManager {
    static let shared = ProcessingPipelineManager()
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "ProcessingPipeline")
    private var activeTasks: [UUID: Task<ProcessingResult, Error>] = [:]
    private let maxConcurrentTasks = Constants.Performance.concurrentOperationLimit
    
    private init() {}
    
    func processMedia(
        _ input: MediaInput,
        configuration: ProcessingConfiguration = .default,
        priority: TaskPriority = .userInitiated
    ) async throws -> ProcessingResult {
        let taskId = UUID()
        
        // Wait if at capacity
        while activeTasks.count >= maxConcurrentTasks {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Create processor
        let processor = UnifiedMediaProcessor(
            ocrService: ServiceContainer.shared.ocrService,
            scriptConversionService: ServiceContainer.shared.scriptConversionService,
            chineseProcessingService: ServiceContainer.shared.chineseProcessingService,
            streamingChineseProcessingService: ServiceContainer.shared.streamingChineseProcessingService,
            mediaStorage: MediaStorageService.shared,
            documentStore: ServiceContainer.shared.documentStore
        )
        
        // Create task
        let task = Task(priority: priority) {
            try await processor.process(input, configuration: configuration)
        }
        
        activeTasks[taskId] = task
        
        do {
            let result = try await task.value
            activeTasks.removeValue(forKey: taskId)
            return result
        } catch {
            activeTasks.removeValue(forKey: taskId)
            throw error
        }
    }
    
    func cancelAll() {
        logger.info("Cancelling all processing tasks")
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}