import Foundation
import AVFoundation
import UIKit
import CoreGraphics

// MARK: - Video Frame Processor
/// Efficiently processes video frames in chunks to avoid memory issues
class VideoFrameProcessor {
    
    struct ProcessedFrame {
        let image: UIImage
        let timestamp: TimeInterval
        let index: Int
    }
    
    struct ProcessingOptions {
        let interval: TimeInterval
        let maxFrames: Int
        let chunkSize: Int
        let compressionQuality: CGFloat
        
        static let `default` = ProcessingOptions(
            interval: Constants.Media.frameExtractionInterval,
            maxFrames: Constants.Media.maxVideoFramesToProcess,
            chunkSize: 10, // Process 10 frames at a time
            compressionQuality: Constants.Media.imageCompressionQuality
        )
    }
    
    private let queue = DispatchQueue(label: "com.snapzify.videoprocessor", qos: .userInitiated)
    private var currentTask: Task<Void, Never>?
    
    // MARK: - Public Methods
    
    /// Process video frames in chunks with progress reporting
    func processVideo(
        at url: URL,
        options: ProcessingOptions = .default,
        progressHandler: @escaping (Double) -> Void,
        frameHandler: @escaping (ProcessedFrame) -> Void
    ) async throws {
        let asset = AVAsset(url: url)
        
        // Load video duration
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Calculate frame times to extract
        let frameCount = min(
            Int(ceil(durationSeconds / options.interval)),
            options.maxFrames
        )
        
        // Process frames in chunks
        let chunks = stride(from: 0, to: frameCount, by: options.chunkSize).map { startIndex in
            let endIndex = min(startIndex + options.chunkSize, frameCount)
            return (startIndex..<endIndex)
        }
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        // Set maximum size to prevent huge images
        imageGenerator.maximumSize = CGSize(
            width: Constants.Media.largeImageMaxDimension,
            height: Constants.Media.largeImageMaxDimension
        )
        
        for (chunkIndex, chunk) in chunks.enumerated() {
            // Check for cancellation
            if Task.isCancelled { break }
            
            // Process chunk
            try await processChunk(
                chunk,
                imageGenerator: imageGenerator,
                interval: options.interval,
                frameHandler: frameHandler
            )
            
            // Report progress
            let progress = Double(chunkIndex + 1) / Double(chunks.count)
            progressHandler(progress)
            
            // Allow other tasks to run
            await Task.yield()
        }
    }
    
    /// Extract a single frame at specific timestamp
    func extractFrame(from videoURL: URL, at timestamp: TimeInterval) async throws -> UIImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        let time = CMTime(seconds: timestamp, preferredTimescale: 600)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to extract frame at \(timestamp): \(error)")
            return nil
        }
    }
    
    /// Generate thumbnail from video
    func generateThumbnail(from videoURL: URL) async throws -> UIImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = Constants.Media.thumbnailSize
        
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to generate thumbnail: \(error)")
            return nil
        }
    }
    
    /// Cancel current processing task
    func cancelProcessing() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    // MARK: - Private Methods
    
    private func processChunk(
        _ range: Range<Int>,
        imageGenerator: AVAssetImageGenerator,
        interval: TimeInterval,
        frameHandler: @escaping (ProcessedFrame) -> Void
    ) async throws {
        // Create times for this chunk
        var times: [NSValue] = []
        for index in range {
            let seconds = Double(index) * interval
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            times.append(NSValue(time: time))
        }
        
        // Use async generation
        return try await withCheckedThrowingContinuation { continuation in
            var processedCount = 0
            let expectedCount = times.count
            
            imageGenerator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cgImage, actualTime, result, error in
                defer {
                    processedCount += 1
                    if processedCount == expectedCount {
                        continuation.resume()
                    }
                }
                
                // Check for errors
                if let error = error {
                    print("Error generating frame: \(error)")
                    return
                }
                
                // Check result
                guard result == .succeeded, let cgImage = cgImage else {
                    print("Failed to generate frame at \(CMTimeGetSeconds(requestedTime))")
                    return
                }
                
                // Convert to UIImage
                let uiImage = UIImage(cgImage: cgImage)
                let timestamp = CMTimeGetSeconds(actualTime)
                let frameIndex = range.lowerBound + processedCount
                
                let processedFrame = ProcessedFrame(
                    image: uiImage,
                    timestamp: timestamp,
                    index: frameIndex
                )
                
                // Call handler on main thread
                Task { @MainActor in
                    frameHandler(processedFrame)
                }
            }
        }
    }
    
    /// Get video dimensions
    func getVideoDimensions(from url: URL) async throws -> CGSize {
        let asset = AVAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.noVideoTrack
        }
        
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        
        // Apply transform to get correct orientation
        let transformedSize = size.applying(transform)
        return CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
    }
    
    /// Estimate memory usage for video processing
    func estimateMemoryUsage(for videoURL: URL) async throws -> Int {
        let dimensions = try await getVideoDimensions(from: videoURL)
        let bytesPerPixel = 4 // RGBA
        let frameSize = Int(dimensions.width * dimensions.height) * bytesPerPixel
        let chunkSize = ProcessingOptions.default.chunkSize
        
        // Estimate: chunk size * frame size * overhead factor
        return frameSize * chunkSize * 2
    }
}

// MARK: - Errors
enum VideoProcessingError: LocalizedError {
    case noVideoTrack
    case processingFailed(String)
    case memoryLimitExceeded
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in file"
        case .processingFailed(let message):
            return "Video processing failed: \(message)"
        case .memoryLimitExceeded:
            return "Video too large to process"
        case .cancelled:
            return "Video processing was cancelled"
        }
    }
}