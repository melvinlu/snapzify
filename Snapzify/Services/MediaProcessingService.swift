import Foundation
import UIKit
import Photos
import AVFoundation
import os.log

// MARK: - Processing Task
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

// MARK: - Processing Progress Delegate
protocol MediaProcessingDelegate: AnyObject {
    func processingDidStart(task: ProcessingTask)
    func processingDidUpdateProgress(taskId: UUID, progress: String, progressValue: Double, processedFrames: Int)
    func processingDidUpdateThumbnail(taskId: UUID, thumbnail: UIImage)
    func processingDidComplete(taskId: UUID, document: Document)
    func processingDidFail(taskId: UUID, error: Error)
}

// MARK: - Media Processing Service
/// Handles all media processing operations extracted from HomeViewModel
@MainActor
class MediaProcessingService {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "MediaProcessingService")
    
    private let store: DocumentStore
    private let ocrService: OCRService
    private let scriptConversionService: ScriptConversionService
    private let chineseProcessingService: ChineseProcessingService
    private let streamingChineseProcessingService: StreamingChineseProcessingService
    private let videoFrameProcessor = VideoFrameProcessor()
    private let mediaStorage = MediaStorageService.shared
    
    weak var delegate: MediaProcessingDelegate?
    
    init(
        store: DocumentStore,
        ocrService: OCRService,
        scriptConversionService: ScriptConversionService,
        chineseProcessingService: ChineseProcessingService,
        streamingChineseProcessingService: StreamingChineseProcessingService
    ) {
        self.store = store
        self.ocrService = ocrService
        self.scriptConversionService = scriptConversionService
        self.chineseProcessingService = chineseProcessingService
        self.streamingChineseProcessingService = streamingChineseProcessingService
    }
    
    // MARK: - Image Processing
    
    func processImage(
        _ image: UIImage,
        source: DocumentSource,
        script: ChineseScript,
        assetIdentifier: String? = nil
    ) async throws -> Document {
        let taskId = UUID()
        
        // Create processing task
        let task = ProcessingTask(
            id: taskId,
            name: "Image",
            progress: "Processing OCR",
            progressValue: 0.1,
            totalFrames: 1,
            processedFrames: 0,
            type: .image,
            thumbnail: generateThumbnail(from: image)
        )
        
        delegate?.processingDidStart(task: task)
        
        do {
            // Perform OCR
            delegate?.processingDidUpdateProgress(
                taskId: taskId,
                progress: "Analyzing text",
                progressValue: 0.3,
                processedFrames: 0
            )
            
            let ocrLines = try await ocrService.recognizeText(in: image)
            
            guard !ocrLines.isEmpty else {
                throw MediaProcessingError.processingFailed("No text found in image")
            }
            
            // Process sentences
            delegate?.processingDidUpdateProgress(
                taskId: taskId,
                progress: "Processing sentences",
                progressValue: 0.5,
                processedFrames: 0
            )
            
            let sentences = await processSentences(from: ocrLines, script: script) { progress in
                self.delegate?.processingDidUpdateProgress(
                    taskId: taskId,
                    progress: "Translating: \(Int(progress * 100))%",
                    progressValue: 0.5 + progress * 0.4,
                    processedFrames: 0
                )
            }
            
            // Save media to file
            guard let imageData = image.jpegData(compressionQuality: Constants.Media.imageCompressionQuality) else {
                throw MediaStorageError.saveFailed(MediaProcessingError.processingFailed("Failed to convert image"))
            }
            
            let mediaURL = try mediaStorage.saveMedia(imageData, id: taskId, isVideo: false)
            let thumbnailURL = try mediaStorage.saveThumbnail(
                generateThumbnail(from: image) ?? image,
                id: taskId
            )
            
            // Create document
            let document = Document(
                id: taskId,
                source: source,
                script: script,
                sentences: sentences,
                mediaURL: mediaURL,
                thumbnailURL: thumbnailURL,
                isVideo: false,
                assetIdentifier: assetIdentifier
            )
            
            // Save to store
            try await store.save(document)
            
            delegate?.processingDidUpdateProgress(
                taskId: taskId,
                progress: "Complete",
                progressValue: 1.0,
                processedFrames: 1
            )
            
            delegate?.processingDidComplete(taskId: taskId, document: document)
            
            return document
            
        } catch {
            delegate?.processingDidFail(taskId: taskId, error: error)
            throw error
        }
    }
    
    // MARK: - Video Processing
    
    func processVideo(
        at url: URL,
        source: DocumentSource,
        script: ChineseScript,
        assetIdentifier: String? = nil
    ) async throws -> Document {
        let taskId = UUID()
        
        // Create processing task
        let task = ProcessingTask(
            id: taskId,
            name: "Video",
            progress: "Extracting frames",
            progressValue: 0.0,
            totalFrames: 0,
            processedFrames: 0,
            type: .video,
            thumbnail: nil
        )
        
        delegate?.processingDidStart(task: task)
        
        do {
            // Generate thumbnail
            if let thumbnail = try await videoFrameProcessor.generateThumbnail(from: url) {
                delegate?.processingDidUpdateThumbnail(taskId: taskId, thumbnail: thumbnail)
            }
            
            // Process frames in chunks
            var allSentences: [Sentence] = []
            var textAppearances: [String: [FrameAppearance]] = [:]
            var frameCount = 0
            
            try await videoFrameProcessor.processVideo(
                at: url,
                progressHandler: { progress in
                    self.delegate?.processingDidUpdateProgress(
                        taskId: taskId,
                        progress: "Processing: \(Int(progress * 100))%",
                        progressValue: progress * 0.7,
                        processedFrames: frameCount
                    )
                },
                frameHandler: { processedFrame in
                    frameCount += 1
                    
                    // Perform OCR on frame
                    Task {
                        if let ocrLines = try? await self.ocrService.recognizeText(in: processedFrame.image) {
                            // Track text appearances
                            for line in ocrLines {
                                let appearance = FrameAppearance(
                                    timestamp: processedFrame.timestamp,
                                    bbox: line.bbox
                                )
                                
                                if textAppearances[line.text] == nil {
                                    textAppearances[line.text] = []
                                }
                                textAppearances[line.text]?.append(appearance)
                            }
                        }
                    }
                }
            )
            
            // Process unique texts into sentences
            delegate?.processingDidUpdateProgress(
                taskId: taskId,
                progress: "Processing text",
                progressValue: 0.8,
                processedFrames: frameCount
            )
            
            for (text, appearances) in textAppearances {
                let sentence = Sentence(
                    text: text,
                    frameAppearances: appearances
                )
                allSentences.append(sentence)
            }
            
            // Translate sentences
            allSentences = await processSentencesWithTranslation(
                allSentences,
                script: script
            ) { progress in
                self.delegate?.processingDidUpdateProgress(
                    taskId: taskId,
                    progress: "Translating: \(Int(progress * 100))%",
                    progressValue: 0.8 + progress * 0.2,
                    processedFrames: frameCount
                )
            }
            
            // Save video data
            let videoData = try Data(contentsOf: url)
            let mediaURL = try mediaStorage.saveMedia(videoData, id: taskId, isVideo: true)
            
            // Generate and save thumbnail
            let thumbnail = try await videoFrameProcessor.generateThumbnail(from: url)
            let thumbnailURL = thumbnail != nil ? 
                try mediaStorage.saveThumbnail(thumbnail!, id: taskId) : nil
            
            // Create document
            let document = Document(
                id: taskId,
                source: source,
                script: script,
                sentences: allSentences,
                mediaURL: mediaURL,
                thumbnailURL: thumbnailURL,
                isVideo: true,
                assetIdentifier: assetIdentifier
            )
            
            // Save to store
            try await store.save(document)
            
            delegate?.processingDidUpdateProgress(
                taskId: taskId,
                progress: "Complete",
                progressValue: 1.0,
                processedFrames: frameCount
            )
            
            delegate?.processingDidComplete(taskId: taskId, document: document)
            
            return document
            
        } catch {
            delegate?.processingDidFail(taskId: taskId, error: error)
            throw error
        }
    }
    
    // MARK: - PHAsset Processing
    
    func processPHAsset(_ asset: PHAsset, script: ChineseScript) async throws -> Document {
        // Determine if image or video
        if asset.mediaType == .image {
            let image = try await loadImage(from: asset)
            return try await processImage(
                image,
                source: .photos,
                script: script,
                assetIdentifier: asset.localIdentifier
            )
        } else if asset.mediaType == .video {
            let videoURL = try await loadVideo(from: asset)
            return try await processVideo(
                at: videoURL,
                source: .photos,
                script: script,
                assetIdentifier: asset.localIdentifier
            )
        } else {
            throw MediaProcessingError.unsupportedMediaType
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func processSentences(
        from ocrLines: [OCRLine],
        script: ChineseScript,
        progressHandler: @escaping (Double) -> Void
    ) async -> [Sentence] {
        var sentences: [Sentence] = []
        
        for (index, line) in ocrLines.enumerated() {
            let sentence = Sentence(
                text: line.text,
                rangeInImage: line.bbox,
                tokens: line.words.map { Token(text: $0.text, bbox: $0.bbox) }
            )
            sentences.append(sentence)
            
            progressHandler(Double(index + 1) / Double(ocrLines.count))
        }
        
        return sentences
    }
    
    private func processSentencesWithTranslation(
        _ sentences: [Sentence],
        script: ChineseScript,
        progressHandler: @escaping (Double) -> Void
    ) async -> [Sentence] {
        // Stream translations if possible
        if streamingChineseProcessingService.isConfigured() {
            return await streamTranslations(
                sentences,
                script: script,
                progressHandler: progressHandler
            )
        } else {
            // Fall back to batch processing
            return await batchTranslations(
                sentences,
                script: script,
                progressHandler: progressHandler
            )
        }
    }
    
    private func streamTranslations(
        _ sentences: [Sentence],
        script: ChineseScript,
        progressHandler: @escaping (Double) -> Void
    ) async -> [Sentence] {
        var processedSentences = sentences
        let texts = sentences.map { $0.text }
        
        do {
            var processedCount = 0
            let totalCount = texts.count
            
            for try await batch in streamingChineseProcessingService.streamBatchProcess(texts, script: script) {
                for (index, result) in batch.enumerated() {
                    if index < processedSentences.count {
                        processedSentences[index].pinyin = result.pinyin
                        processedSentences[index].english = result.english
                        processedSentences[index].status = .translated
                    }
                }
                
                processedCount = min(processedCount + batch.count, totalCount)
                progressHandler(Double(processedCount) / Double(totalCount))
            }
        } catch {
            logger.error("Stream translation failed: \(error)")
        }
        
        return processedSentences
    }
    
    private func batchTranslations(
        _ sentences: [Sentence],
        script: ChineseScript,
        progressHandler: @escaping (Double) -> Void
    ) async -> [Sentence] {
        var processedSentences = sentences
        let batchSize = Constants.TextProcessing.batchTranslationSize
        
        for batchStart in stride(from: 0, to: sentences.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, sentences.count)
            let batch = Array(sentences[batchStart..<batchEnd])
            let texts = batch.map { $0.text }
            
            do {
                let results = try await chineseProcessingService.processBatch(texts, script: script)
                
                for (index, result) in results.enumerated() {
                    let sentenceIndex = batchStart + index
                    if sentenceIndex < processedSentences.count {
                        processedSentences[sentenceIndex].pinyin = result.pinyin
                        processedSentences[sentenceIndex].english = result.english
                        processedSentences[sentenceIndex].status = .translated
                    }
                }
            } catch {
                logger.error("Batch translation failed: \(error)")
            }
            
            progressHandler(Double(batchEnd) / Double(sentences.count))
        }
        
        return processedSentences
    }
    
    private func generateThumbnail(from image: UIImage) -> UIImage? {
        return mediaStorage.generateThumbnail(
            from: image.jpegData(compressionQuality: 0.9) ?? Data(),
            targetSize: Constants.Media.thumbnailSize
        )
    }
    
    private func loadImage(from asset: PHAsset) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let image = image {
                    continuation.resume(returning: image)
                } else {
                    let error = info?[PHImageErrorKey] as? Error ?? 
                        MediaProcessingError.processingFailed("Failed to load image")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func loadVideo(from asset: PHAsset) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, info in
                guard let urlAsset = avAsset as? AVURLAsset else {
                    let error = info?[PHImageErrorKey] as? Error ?? 
                        MediaProcessingError.processingFailed("Failed to load video")
                    continuation.resume(throwing: error)
                    return
                }
                
                continuation.resume(returning: urlAsset.url)
            }
        }
    }
}

// MARK: - Processing Errors
enum ProcessingError: LocalizedError {
    case noFramesExtracted
    case ocrFailed
    case invalidMedia
    
    var errorDescription: String? {
        switch self {
        case .noFramesExtracted:
            return "Failed to extract frames from video"
        case .ocrFailed:
            return "Text recognition failed"
        case .invalidMedia:
            return "Invalid media format"
        }
    }
}