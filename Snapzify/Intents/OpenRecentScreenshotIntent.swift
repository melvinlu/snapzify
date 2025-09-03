import AppIntents
import Photos
import UIKit
import SwiftUI
import os.log

struct OpenRecentScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recent Screenshot"
    static var description = IntentDescription("Opens the most recent screenshot from your photo library in Snapzify")
    
    // This makes it open the app
    static var openAppWhenRun: Bool = true
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "OpenIntent")
    
    @MainActor
    func perform() async throws -> some IntentResult {
        logger.info("Starting open recent screenshot intent")
        
        // Show loading screen immediately
        AppState.shared.isProcessingScreenshot = true
        
        // Request photo library access
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else {
            AppState.shared.isProcessingScreenshot = false
            logger.error("Photo library access denied")
            throw IntentError.permissionDenied
        }
        
        // Get the most recent screenshot
        guard let screenshot = getMostRecentScreenshot() else {
            AppState.shared.isProcessingScreenshot = false
            logger.error("No recent screenshot found")
            throw IntentError.noScreenshotFound
        }
        
        // Load the image
        guard let image = await loadImage(from: screenshot) else {
            AppState.shared.isProcessingScreenshot = false
            logger.error("Failed to load screenshot image")
            throw IntentError.imageLoadFailed
        }
        
        // Save to Documents directory for processing
        guard let savedURL = saveImageToDocuments(image) else {
            AppState.shared.isProcessingScreenshot = false
            logger.error("Failed to save image to documents")
            throw OpenIntentError.saveFailed
        }
        
        // Process the image and get document
        let document = await processImage(at: savedURL)
        
        if let document = document {
            logger.info("Successfully processed screenshot, opening in app")
            logger.info("Document ID: \(document.id), sentences: \(document.sentences.count)")
            
            // Save the document to the store first
            let documentStore = ServiceContainer.shared.documentStore
            do {
                try await documentStore.save(document)
                logger.info("Document saved to store")
            } catch {
                logger.error("Failed to save document: \(error)")
            }
            
            // Set the document in app state for navigation
            // The processing view will dismiss itself when it sees the document is ready
            await MainActor.run {
                logger.info("Setting pending document in AppState")
                AppState.shared.pendingDocument = document
                AppState.shared.shouldNavigateToDocument = true
                logger.info("AppState updated - shouldNavigate: \(AppState.shared.shouldNavigateToDocument)")
            }
            
            return .result()
        } else {
            AppState.shared.isProcessingScreenshot = false
            logger.error("Failed to process screenshot")
            throw OpenIntentError.processingFailed
        }
    }
    
    private func getMostRecentScreenshot() -> PHAsset? {
        let fetchOptions = PHFetchOptions()
        
        // Filter for screenshots taken in the last 24 hours (more lenient than queue)
        let oneDayAgo = Date().addingTimeInterval(-86400)
        fetchOptions.predicate = NSPredicate(
            format: "(mediaType == %d) AND (mediaSubtype & %d != 0) AND (creationDate >= %@)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue,
            oneDayAgo as NSDate
        )
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let result = PHAsset.fetchAssets(with: fetchOptions)
        return result.firstObject
    }
    
    @MainActor
    private func loadImage(from asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    self.logger.error("Failed to load image: \(error)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    private func saveImageToDocuments(_ image: UIImage) -> URL? {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            logger.error("Failed to convert image to data")
            return nil
        }
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "intent_screenshot_\(UUID().uuidString).jpg"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            try imageData.write(to: fileURL)
            logger.info("Saved image to \(fileURL.path)")
            return fileURL
        } catch {
            logger.error("Failed to save image: \(error)")
            return nil
        }
    }
    
    @MainActor
    private func processImage(at url: URL) async -> Document? {
        // Use the proper processing pipeline to get sentences with bounding boxes
        let serviceContainer = ServiceContainer.shared
        let homeViewModel = serviceContainer.makeHomeViewModel(
            onOpenSettings: { },
            onOpenDocument: { _ in }
        )
        
        do {
            if let imageData = try? Data(contentsOf: url),
               let image = UIImage(data: imageData) {
                
                // Process the image using the full pipeline to get proper sentences with bounding boxes
                let document = try await homeViewModel.processImageForQueue(image)
                
                // Update the document with our URL and metadata
                var updatedDocument = document
                updatedDocument.mediaURL = url
                updatedDocument.customName = "Screenshot"
                
                return updatedDocument
            }
        } catch {
            logger.error("Failed to process screenshot: \(error)")
        }
        
        return nil
    }
}


// Errors shared with QueueRecentScreenshotIntent
enum OpenIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case saveFailed
    case processingFailed
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .saveFailed:
            return "Failed to save image"
        case .processingFailed:
            return "Failed to process screenshot"
        }
    }
}