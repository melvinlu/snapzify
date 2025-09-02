import AppIntents
import Photos
import UIKit
import SwiftUI
import os.log

struct QueueRecentScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Queue Recent Screenshot"
    static var description = IntentDescription("Queues the most recent screenshot from your photo library to Snapzify")
    
    // This makes it available in Shortcuts and Action Button
    static var openAppWhenRun: Bool = false
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "QueueIntent")
    
    @MainActor
    func perform() async throws -> some IntentResult {
        logger.info("Starting queue recent screenshot intent")
        
        // Request photo library access
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else {
            logger.error("Photo library access denied")
            throw IntentError.permissionDenied
        }
        
        // Get the most recent screenshot
        guard let screenshot = getMostRecentScreenshot() else {
            logger.error("No recent screenshot found")
            throw IntentError.noScreenshotFound
        }
        
        // Load the image
        guard let image = await loadImage(from: screenshot) else {
            logger.error("Failed to load screenshot image")
            throw IntentError.imageLoadFailed
        }
        
        // Save to queue
        let success = await queueImage(image)
        
        if success {
            logger.info("Successfully queued screenshot")
            return .result()
        } else {
            logger.error("Failed to queue screenshot")
            throw IntentError.queueFailed
        }
    }
    
    private func getMostRecentScreenshot() -> PHAsset? {
        let fetchOptions = PHFetchOptions()
        
        // Filter for screenshots taken in the last 30 seconds
        let thirtySecondsAgo = Date().addingTimeInterval(-30)
        fetchOptions.predicate = NSPredicate(
            format: "(mediaType == %d) AND (mediaSubtype & %d != 0) AND (creationDate >= %@)",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue,
            thirtySecondsAgo as NSDate
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
    
    private func queueImage(_ image: UIImage) async -> Bool {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            logger.error("Failed to convert image to data")
            return false
        }
        
        // Get shared container
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) else {
            logger.error("Failed to get shared container")
            return false
        }
        
        // Create queue directory
        let queueDirectory = containerURL.appendingPathComponent("QueuedMedia")
        try? FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        
        // Generate unique filename
        let fileName = "screenshot_\(UUID().uuidString).jpg"
        let fileURL = queueDirectory.appendingPathComponent(fileName)
        
        // Save image
        do {
            try imageData.write(to: fileURL)
            logger.info("Saved image to \(fileURL.path)")
        } catch {
            logger.error("Failed to save image: \(error)")
            return false
        }
        
        // Create queue item
        let queueItem = QueueItem(
            id: UUID().uuidString,
            fileName: fileName,
            isVideo: false,
            queuedAt: Date(),
            source: "ActionButton"
        )
        
        // Load existing queue
        let queueFileURL = containerURL.appendingPathComponent("mediaQueue.json")
        var queueItems: [QueueItem] = []
        
        if let data = try? Data(contentsOf: queueFileURL),
           let existingItems = try? JSONDecoder().decode([QueueItem].self, from: data) {
            queueItems = existingItems
        }
        
        // Add new item
        queueItems.append(queueItem)
        
        // Save updated queue
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(queueItems)
            try data.write(to: queueFileURL)
            logger.info("Successfully added to queue: \(queueItems.count) items total")
            return true
        } catch {
            logger.error("Failed to update queue file: \(error)")
            // Try to clean up the saved image
            try? FileManager.default.removeItem(at: fileURL)
            return false
        }
    }
}

// QueueItem is imported from the shared Models/QueueItem.swift file

// Custom errors
enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case permissionDenied
    case noScreenshotFound
    case imageLoadFailed
    case queueFailed
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .permissionDenied:
            return "Photo library access is required"
        case .noScreenshotFound:
            return "No recent screenshot found (must be taken within last 30 seconds)"
        case .imageLoadFailed:
            return "Failed to load screenshot"
        case .queueFailed:
            return "Failed to add to queue"
        }
    }
}

// App Shortcuts provider
struct SnapzifyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QueueRecentScreenshotIntent(),
            phrases: [
                "Queue screenshot in \(.applicationName)",
                "Add screenshot to \(.applicationName)",
                "Queue recent screenshot in \(.applicationName)"
            ],
            shortTitle: "Queue Screenshot",
            systemImageName: "photo.badge.plus"
        )
    }
}