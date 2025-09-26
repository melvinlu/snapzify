import Foundation
import SwiftUI
import UIKit
import CoreImage
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
    @Published var showConversation = false
    @Published var showCamera = false
    @Published var capturedImage: UIImage?
    @Published var showCaptureResult = false
    @Published var capturedText: String = ""
    @Published var appendMode: Bool = false
    @Published var errorMessage: String?
    @Published var processingProgress: String = ""
    @Published var activeProcessingTasks: [ProcessingTask] = []
    
    // Unified input text for both translate and ask
    @Published var unifiedInputText: String = ""
    
    // Translation properties
    @Published var isProcessingTranslation: Bool = false
    @Published var translationResult: String = ""
    @Published var translationFollowUp: String = ""
    @Published var translationHistory: [String] = []
    @Published var isTranslationExpanded: Bool = false
    
    // Ask expert properties
    @Published var isAsking: Bool = false
    @Published var askResult: String = ""
    @Published var askFollowUp: String = ""
    @Published var askHistory: [String] = []
    @Published var isAskExpanded: Bool = false
    
    // Audio recording properties
    @Published var isRecording: Bool = false
    @Published var isProcessingAudio: Bool = false
    @Published var audioFeedback: String = ""
    @Published var audioFollowUp: String = ""
    @Published var isAudioExpanded: Bool = false
    @Published var isRecordingUnified: Bool = false
    @Published var isProcessingUnifiedAudio: Bool = false
    private var audioRecorder: AVAudioRecorder?
    private var unifiedAudioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    private var recordingURL: URL?
    private var pronunciationHistory: [String] = [] // Track conversation history for context
    private var audioProcessingTask: Task<Void, Never>?
    
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
    private let configService: ConfigService = ServiceContainer.shared.configService
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

    func openCamera() {
        showCamera = true
    }

    func processCapturedImage(_ image: UIImage) async {
        let sessionId = UUID().uuidString.prefix(8)
        print("\n🔍 === OCR Session \(sessionId) Starting ===")
        print("Append mode: \(appendMode)")

        // Store previous text if in append mode
        let previousText = appendMode ? capturedText : ""

        // Clear state for new capture (but preserve text if appending)
        await MainActor.run {
            if !appendMode {
                capturedText = ""
            }
            capturedImage = nil
        }

        // Store original image for display
        capturedImage = image
        isProcessing = true

        do {
            // Preprocess image for better OCR
            let preprocessedImage = preprocessImageForOCR(image)

            // Perform OCR on preprocessed image
            print("[\(sessionId)] Starting OCR on preprocessed image: \(preprocessedImage.size)")
            let ocrLines = try await ocrService.recognizeText(in: preprocessedImage)

            // Debug: Log raw OCR results
            print("[\(sessionId)] === OCR Debug ===")
            print("[\(sessionId)] Total OCR lines detected: \(ocrLines.count)")
            print("[\(sessionId)] Image dimensions: \(preprocessedImage.size)")
            for (index, line) in ocrLines.enumerated() {
                print("Line \(index): '\(line.text)' at x:\(line.bbox.minX), y:\(line.bbox.minY), width:\(line.bbox.width), height:\(line.bbox.height)")
            }

            // Filter to only Chinese text with bounds checking
            let imageWidth = image.size.width
            let imageHeight = image.size.height

            let chineseOnlyLines = ocrLines.filter { line in
                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Check if bounding box is within image bounds
                let isInBounds = line.bbox.minX >= 0 &&
                                line.bbox.minY >= 0 &&
                                line.bbox.maxX <= imageWidth &&
                                line.bbox.maxY <= imageHeight

                let hasChinese = containsChinese(trimmed)

                if hasChinese {
                    if !isInBounds {
                        print("  ⚠️ OUT OF BOUNDS Chinese text: '\(line.text)' at x:\(line.bbox.minX), y:\(line.bbox.minY), maxX:\(line.bbox.maxX), maxY:\(line.bbox.maxY)")
                    } else {
                        print("  ✓ Valid Chinese: '\(line.text)' at x:\(line.bbox.minX), y:\(line.bbox.minY)")
                    }
                }

                return !trimmed.isEmpty && hasChinese && isInBounds
            }

            print("\nFiltered Chinese lines: \(chineseOnlyLines.count)")
            print("Image size: width=\(image.size.width), height=\(image.size.height)")
            for (index, line) in chineseOnlyLines.enumerated() {
                print("Chinese line \(index): '\(line.text)' at x:\(line.bbox.minX), y:\(line.bbox.minY)")
            }

            guard !chineseOnlyLines.isEmpty else {
                await MainActor.run {
                    errorMessage = "No Chinese text found in image"
                    isProcessing = false
                }
                return
            }

            // Group text into likely subtitle blocks based on X position alignment
            // Subtitles usually have similar X positions (vertically aligned)
            var textGroups: [[OCRLine]] = []

            for line in chineseOnlyLines {
                var foundGroup = false

                // Check if this line belongs to an existing group (similar X position)
                for i in 0..<textGroups.count {
                    if let firstInGroup = textGroups[i].first {
                        // If X positions are within 100 pixels, consider them part of same subtitle column
                        if abs(line.bbox.minX - firstInGroup.bbox.minX) < 100 {
                            textGroups[i].append(line)
                            foundGroup = true
                            break
                        }
                    }
                }

                if !foundGroup {
                    textGroups.append([line])
                }
            }

            // Filter out noise groups and keep significant ones (more than 2 characters)
            let significantGroups = textGroups.filter { group in
                group.count > 2 || group.reduce(0, { $0 + $1.text.count }) > 2
            }

            print("\nFound \(textGroups.count) text groups:")
            for (index, group) in textGroups.enumerated() {
                let groupText = group.map { $0.text }.joined(separator: "")
                print("  Group \(index) (\(group.count) items): '\(groupText)' at X≈\(group.first?.bbox.minX ?? 0)")
            }
            print("Processing \(significantGroups.count) significant groups")

            // Process all significant groups
            var allFilteredLines: [OCRLine] = []

            for group in significantGroups {
                let filteredGroup = group.filter { line in
                    // Filter out very small text (likely UI elements)
                    let minTextHeight: CGFloat = 15  // Lowered threshold
                    if line.bbox.height < minTextHeight {
                        print("  ⚠️ Filtered out small text: '\(line.text)' height=\(line.bbox.height)")
                        return false
                    }

                    // For groups with many items (likely subtitles), keep all characters
                    // Only filter single chars if the group is small (likely noise)
                    if group.count < 5 && line.text.count == 1 {
                        // Only filter if it's truly isolated
                        let currentY = line.bbox.minY
                        let hasNearbyText = group.contains { other in
                            other.text != line.text && abs(other.bbox.minY - currentY) < 150
                        }
                        if !hasNearbyText {
                            print("  ⚠️ Filtered out isolated single char: '\(line.text)'")
                            return false
                        }
                    }

                    return true
                }
                allFilteredLines.append(contentsOf: filteredGroup)
            }

            // Sort all lines by X position (for columns) then by Y position within each column
            let sortedLines = allFilteredLines.sorted { line1, line2 in
                // If X positions are significantly different (different columns), sort by X (right to left)
                if abs(line1.bbox.minX - line2.bbox.minX) > 100 {
                    return line1.bbox.minX > line2.bbox.minX  // Right to left for vertical Chinese
                }
                // Otherwise sort by Y position (top to bottom)
                return line1.bbox.minY < line2.bbox.minY
            }

            // For vertical text, reverse to get correct reading order
            let finalLines = Array(sortedLines.reversed())

            // Combine the text - no spaces for vertical Chinese text
            let newText = finalLines.map { $0.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }.joined(separator: "")

            // Append to previous text if in append mode
            let combinedText = appendMode ? previousText + newText : newText

            print("\nFinal combined text: '\(combinedText)'")
            if appendMode {
                print("Appended to previous text: '\(previousText)'")
            }
            print("=== End OCR Debug ===\n")

            await MainActor.run {
                capturedText = combinedText
                isProcessing = false
                showCaptureResult = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to process image: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }

    private func preprocessImageForOCR(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let context = CIContext(options: nil)

        // Apply filters sequentially
        var processedImage = ciImage

        // 1. Convert to grayscale
        if let grayscaleFilter = CIFilter(name: "CIColorControls") {
            grayscaleFilter.setValue(processedImage, forKey: kCIInputImageKey)
            grayscaleFilter.setValue(0.0, forKey: kCIInputSaturationKey)
            if let output = grayscaleFilter.outputImage {
                processedImage = output
            }
        }

        // 2. Increase contrast moderately
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(processedImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.2, forKey: kCIInputContrastKey)  // Moderate contrast increase (1.0 is normal)
            contrastFilter.setValue(0.05, forKey: kCIInputBrightnessKey) // Very slight brightness increase
            if let output = contrastFilter.outputImage {
                processedImage = output
            }
        }

        // 3. Sharpen the image
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(processedImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.8, forKey: kCIInputSharpnessKey)
            if let output = sharpenFilter.outputImage {
                processedImage = output
            }
        }

        // 4. Reduce noise
        if let noiseReductionFilter = CIFilter(name: "CINoiseReduction") {
            noiseReductionFilter.setValue(processedImage, forKey: kCIInputImageKey)
            noiseReductionFilter.setValue(0.02, forKey: "inputNoiseLevel")
            noiseReductionFilter.setValue(0.4, forKey: "inputSharpness")
            if let output = noiseReductionFilter.outputImage {
                processedImage = output
            }
        }

        // 5. Apply moderate exposure adjustment
        if let exposureFilter = CIFilter(name: "CIExposureAdjust") {
            exposureFilter.setValue(processedImage, forKey: kCIInputImageKey)
            exposureFilter.setValue(0.3, forKey: kCIInputEVKey) // Moderate exposure increase
            if let output = exposureFilter.outputImage {
                processedImage = output
            }
        }

        // Convert back to UIImage
        if let cgImage = context.createCGImage(processedImage, from: processedImage.extent) {
            let finalImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
            print("Image preprocessed: Original size \(image.size), Processed size \(finalImage.size)")
            return finalImage
        }

        print("Image preprocessing failed, returning original")
        return image
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
               (0xF900...0xFAFF).contains(scalar.value) ||
               (0x2F800...0x2FA1F).contains(scalar.value) {
                return true
            }
        }
        return false
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
    
    // MARK: - Collapse/Expand Methods
    
    func collapseAllSections() {
        isTranslationExpanded = false
        isAskExpanded = false
        isAudioExpanded = false
    }
    
    func expandTranslationSection() {
        isTranslationExpanded = true
        isAskExpanded = false
        isAudioExpanded = false
    }
    
    func expandAskSection() {
        isAskExpanded = true
        isTranslationExpanded = false
        isAudioExpanded = false
    }
    
    func expandAudioSection() {
        isAudioExpanded = true
        isTranslationExpanded = false
        isAskExpanded = false
    }
    
    // MARK: - Translation/Breakdown
    
    private func containsChineseCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for CJK Unified Ideographs range
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
    
    func performTranslation() async {
        guard !unifiedInputText.isEmpty else {
            print("DEBUG: Cannot perform translation - no text")
            return
        }
        guard englishToChineseService.isConfigured() else {
            print("DEBUG: Service not configured")
            await MainActor.run {
                errorMessage = "OpenAI API key not configured. Please add it in Settings."
            }
            return
        }
        
        let queryText = unifiedInputText
        let isChineseInput = containsChineseCharacters(queryText)
        
        // Save the query to show as header
        UserDefaults.standard.set(queryText, forKey: isChineseInput ? "currentBreakdownQuery" : "currentTranslationQuery")
        
        print("DEBUG: Starting \(isChineseInput ? "breakdown" : "translation") for: \(queryText)")
        await MainActor.run {
            isProcessingTranslation = true
            translationResult = ""
            // Don't clear the unified input - user might want to use it for Ask
            expandTranslationSection()
        }
        
        do {
            // Choose the appropriate stream based on input language
            let stream = isChineseInput ? 
                englishToChineseService.streamBreakdown(queryText) : 
                englishToChineseService.streamTranslate(queryText)
            
            for try await chunk in stream {
                await MainActor.run {
                    self.translationResult += chunk
                }
            }
            
            await MainActor.run {
                self.isProcessingTranslation = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "\(isChineseInput ? "Breakdown" : "Translation") failed: \(error.localizedDescription)"
                self.isProcessingTranslation = false
            }
        }
    }
    
    // MARK: - Reverse Snapzify
    
    func performAsk() async {
        guard !unifiedInputText.isEmpty else {
            print("DEBUG: Cannot perform ask - no text")
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
        let queryText = unifiedInputText
        UserDefaults.standard.set(queryText, forKey: "currentAskQuery")
        
        print("DEBUG: Starting ask for: \(queryText)")
        await MainActor.run {
            isAsking = true
            // Add previous Q&A to history if exists
            if !askResult.isEmpty {
                if let previousQ = UserDefaults.standard.string(forKey: "currentAskQuery") {
                    askHistory.append("Q: \(previousQ)")
                    askHistory.append("A: \(askResult)")
                }
            }
            askResult = ""
            // Don't clear the unified input - user might want to use it for Translate
            expandAskSection()
        }
        
        do {
            let stream = englishToChineseService.streamAskWithHistory(queryText, history: askHistory)
            
            for try await chunk in stream {
                await MainActor.run {
                    self.askResult += chunk
                }
            }
            
            await MainActor.run {
                self.isAsking = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Ask failed: \(error.localizedDescription)"
                self.isAsking = false
            }
        }
    }
    
    func performAskFollowUp() async {
        guard !askFollowUp.isEmpty else {
            print("DEBUG: Cannot perform follow-up - no text")
            return
        }
        
        // Store current result before clearing
        let previousResult = askResult
        let previousQuestion = UserDefaults.standard.string(forKey: "currentAskQuery") ?? ""
        
        // Update the header to show the follow-up question
        UserDefaults.standard.set(askFollowUp, forKey: "currentAskQuery")
        
        await MainActor.run {
            // Update unified input to reflect what's being asked
            unifiedInputText = askFollowUp
            isAsking = true
            askResult = ""
        }
        
        // Add current Q&A to history for context
        if !previousResult.isEmpty {
            askHistory.append("User asked: \(previousQuestion)")
            askHistory.append("Response: \(previousResult)")
        }
        
        // Process follow-up with context
        let followUpText = askFollowUp
        
        // Clear follow-up field
        await MainActor.run {
            askFollowUp = ""
        }
        
        // Build a contextual prompt that includes the previous response
        let contextualPrompt = """
        Based on this previous response:
        ---
        \(previousResult)
        ---
        
        User's follow-up question: \(followUpText)
        """
        
        // Use askWithHistory for contextual follow-up
        let stream = englishToChineseService.streamAskWithHistory(contextualPrompt, history: askHistory)
        
        do {
            for try await chunk in stream {
                await MainActor.run {
                    askResult += chunk
                }
            }
            
            // Add to history
            askHistory.append("Follow-up: \(followUpText)")
            askHistory.append("Response: \(askResult)")
            
            // Keep history limited
            if askHistory.count > 20 {
                askHistory = Array(askHistory.suffix(20))
            }
        } catch {
            await MainActor.run {
                askResult = "Error: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isAsking = false
        }
    }
    
    // performBreakdown() removed - now handled by performTranslation()
    
    func performTranslationFollowUp() async {
        guard !translationFollowUp.isEmpty else {
            print("DEBUG: Cannot perform follow-up - no text")
            return
        }
        
        // Store current result before clearing
        let previousResult = translationResult
        let previousInput = UserDefaults.standard.string(forKey: "currentTranslationQuery") ?? UserDefaults.standard.string(forKey: "currentBreakdownQuery") ?? ""
        
        // Update the header to show the follow-up query
        // Detect if follow-up is Chinese or English
        let followUpIsChineseInput = translationFollowUp.range(of: "\\p{Script=Han}", options: .regularExpression) != nil
        UserDefaults.standard.set(translationFollowUp, forKey: followUpIsChineseInput ? "currentBreakdownQuery" : "currentTranslationQuery")
        
        await MainActor.run {
            // Update unified input to reflect what's being translated
            unifiedInputText = translationFollowUp
            isProcessingTranslation = true
            translationResult = ""
        }
        
        // Add current translation to history for context
        if !previousResult.isEmpty {
            translationHistory.append("User input: \(previousInput)")
            translationHistory.append("Response: \(previousResult)")
        }
        
        // Process follow-up with context
        let followUpText = translationFollowUp
        
        // Clear follow-up field
        await MainActor.run {
            translationFollowUp = ""
        }
        
        // Build a contextual prompt that includes the previous response
        let contextualPrompt = """
        Based on this previous response:
        ---
        \(previousResult)
        ---
        
        User's follow-up question: \(followUpText)
        """
        
        // Use askWithHistory for contextual follow-up
        let stream = englishToChineseService.streamAskWithHistory(contextualPrompt, history: translationHistory)
        
        do {
            for try await chunk in stream {
                await MainActor.run {
                    translationResult += chunk
                }
            }
            
            // Add to history
            translationHistory.append("Follow-up: \(followUpText)")
            translationHistory.append("Response: \(translationResult)")
            
            // Keep history limited
            if translationHistory.count > 20 {
                translationHistory = Array(translationHistory.suffix(20))
            }
        } catch {
            await MainActor.run {
                translationResult = "Error: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isProcessingTranslation = false
        }
    }
    
    // MARK: - Audio Recording
    
    func startRecording() {
        if isRecording {
            stopRecording()
        } else {
            requestMicrophonePermission { [weak self] granted in
                if granted {
                    Task { @MainActor in
                        self?.beginRecording()
                    }
                }
            }
        }
    }
    
    func cancelAudioProcessing() {
        // Cancel the current processing task
        audioProcessingTask?.cancel()
        audioProcessingTask = nil
        
        // Reset state
        isProcessingAudio = false
        audioFeedback = ""
        audioFollowUp = ""
        
        // Clean up recording file if it exists
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
    
    func performAudioFollowUp() async {
        guard !audioFollowUp.isEmpty else {
            print("DEBUG: Cannot perform audio follow-up - no text")
            return
        }
        
        // Store current feedback before clearing
        let previousFeedback = audioFeedback
        
        await MainActor.run {
            isProcessingAudio = true
            audioFeedback = ""
            expandAudioSection()
        }
        
        // Process follow-up with context
        let followUpText = audioFollowUp
        
        // Clear follow-up field
        await MainActor.run {
            audioFollowUp = ""
        }
        
        // Build a contextual prompt that includes the previous feedback
        let contextualPrompt = """
        Based on this previous pronunciation feedback:
        ---
        \(previousFeedback)
        ---
        
        User's follow-up question: \(followUpText)
        """
        
        // Use context-aware streaming with the full context
        let stream = englishToChineseService.streamAskWithHistory(contextualPrompt, history: pronunciationHistory)
        
        audioProcessingTask = Task {
            do {
                for try await chunk in stream {
                    // Check for cancellation
                    if Task.isCancelled {
                        break
                    }
                    
                    await MainActor.run {
                        audioFeedback += chunk
                    }
                }
                
                // Add to history if not cancelled
                if !Task.isCancelled {
                    pronunciationHistory.append("Follow-up: \(followUpText)")
                    pronunciationHistory.append("Response: \(audioFeedback)")
                    
                    // Keep history limited
                    if pronunciationHistory.count > 20 {
                        pronunciationHistory = Array(pronunciationHistory.suffix(20))
                    }
                }
            } catch {
                // Don't show error if cancelled
                if !Task.isCancelled {
                    await MainActor.run {
                        audioFeedback = "Error: \(error.localizedDescription)"
                    }
                }
            }
            
            await MainActor.run {
                isProcessingAudio = false
            }
        }
    }
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                completion(granted)
            }
        @unknown default:
            completion(false)
        }
    }
    
    private func beginRecording() {
        do {
            // Configure audio session
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // Create recording URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            recordingURL = documentsPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
            
            // Configure recorder settings
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            // Create and start recorder
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()
            
            isRecording = true
            print("DEBUG: Started recording to \(recordingURL!)")
        } catch {
            print("DEBUG: Failed to start recording: \(error)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        isRecording = false
        
        if let url = recordingURL {
            print("DEBUG: Stopped recording, file at: \(url)")
            audioProcessingTask = Task {
                await processRecording(url: url)
            }
        }
    }
    
    private func processRecording(url: URL) async {
        await MainActor.run {
            isProcessingAudio = true
            audioFeedback = ""
            expandAudioSection()
        }
        
        do {
            // Check for cancellation before transcription
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isProcessingAudio = false
                }
                try? FileManager.default.removeItem(at: url)
                return
            }
            
            // First, transcribe the audio using Whisper
            let transcription = try await transcribeAudio(url: url)
            print("DEBUG: Transcription: \(transcription)")
            
            // Check for cancellation after transcription
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isProcessingAudio = false
                }
                try? FileManager.default.removeItem(at: url)
                return
            }
            
            // Add the transcription to history for context
            pronunciationHistory.append("Student said: \"\(transcription)\"")
            
            // Stream the feedback response
            await streamFeedbackOnPronunciation(transcription: transcription)
            
            // Only update history if not cancelled
            if !Task.isCancelled {
                // Add the feedback to history (but limit history size)
                let finalFeedback = audioFeedback
                pronunciationHistory.append(finalFeedback)
                
                // Keep only last 10 exchanges (20 items total)
                if pronunciationHistory.count > 20 {
                    pronunciationHistory = Array(pronunciationHistory.suffix(20))
                }
            }
            
            await MainActor.run {
                self.isProcessingAudio = false
            }
            
            // Clean up the recording file
            try? FileManager.default.removeItem(at: url)
        } catch {
            // Don't show error if cancelled
            if !Task.isCancelled {
                await MainActor.run {
                    self.errorMessage = "Failed to process recording: \(error.localizedDescription)"
                    self.isProcessingAudio = false
                }
            }
        }
    }
    
    private func transcribeAudio(url: URL) async throws -> String {
        guard let key = configService.openAIKey,
              !key.isEmpty else {
            throw EnglishChineseTranslationError.notConfigured
        }
        
        let whisperURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: whisperURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add language parameter (Chinese)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("zh\r\n".data(using: .utf8)!)
        
        // Add audio file
        let audioData = try Data(contentsOf: url)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text
        }
        
        throw EnglishChineseTranslationError.invalidResponse
    }
    
    private func streamFeedbackOnPronunciation(transcription: String) async {
        // Check API key from configService
        guard let key = configService.openAIKey,
              !key.isEmpty else {
            await MainActor.run {
                audioFeedback = "OpenAI API key not configured"
            }
            return
        }
        
        // Use context-aware feedback if we have history, otherwise use regular feedback
        let stream = pronunciationHistory.isEmpty ?
            englishToChineseService.streamPronunciationFeedback(transcription) :
            englishToChineseService.streamPronunciationFeedbackWithContext(transcription, previousFeedback: pronunciationHistory)
        
        do {
            for try await chunk in stream {
                // Check for cancellation
                if Task.isCancelled {
                    break
                }
                
                await MainActor.run {
                    audioFeedback += chunk
                }
            }
        } catch {
            // Don't show error if cancelled
            if !Task.isCancelled {
                await MainActor.run {
                    audioFeedback = "Error getting feedback: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // Removed old functions - performReverseSnapzify and performBreakdown
    // These are now handled by performTranslation() which automatically detects
    // whether to translate English or breakdown Chinese
    
    // MARK: - Audio Recording for Unified Input
    
    func startRecordingUnified() {
        if isRecordingUnified {
            stopRecordingUnified()
        } else {
            requestMicrophonePermission { [weak self] granted in
                if granted {
                    Task { @MainActor in
                        self?.beginRecordingUnified()
                    }
                }
            }
        }
    }
    
    func stopRecordingUnified() {
        guard isRecordingUnified else { return }
        
        unifiedAudioRecorder?.stop()
        isRecordingUnified = false
        
        if let url = recordingURL {
            print("DEBUG: Stopped recording for unified input, file at: \(url)")
            Task {
                await processUnifiedRecording(url: url)
            }
        }
    }
    
    private func beginRecordingUnified() {
        do {
            // Configure audio session
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            // Create recording URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            recordingURL = documentsPath.appendingPathComponent("unified_recording_\(Date().timeIntervalSince1970).m4a")
            
            // Configure recorder
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            unifiedAudioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            unifiedAudioRecorder?.delegate = nil
            unifiedAudioRecorder?.record()
            
            isRecordingUnified = true
            print("DEBUG: Started recording for unified input to \(recordingURL!)")
        } catch {
            print("DEBUG: Failed to start recording for unified input: \(error)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func processUnifiedRecording(url: URL) async {
        await MainActor.run {
            isProcessingUnifiedAudio = true
            unifiedInputText = "Transcribing..."
        }
        
        do {
            // Transcribe the audio
            let transcription = try await transcribeAudio(url: url)
            
            await MainActor.run {
                // Set the transcribed text as the unified input
                unifiedInputText = transcription
                isProcessingUnifiedAudio = false
                // User will choose whether to translate or ask
            }
            
            // Clean up the recording file
            try? FileManager.default.removeItem(at: url)
        } catch {
            await MainActor.run {
                unifiedInputText = ""
                errorMessage = "Failed to transcribe audio: \(error.localizedDescription)"
                isProcessingUnifiedAudio = false
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
