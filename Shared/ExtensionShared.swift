import Foundation
import UIKit
import UniformTypeIdentifiers

// MARK: - Shared Extension Components
// This file contains shared code for both ActionExtension and QueueActionExtension
// It should be included in both extension targets to eliminate duplication

// MARK: - Extension Constants
enum ExtensionConstants {
    static let appGroupIdentifier = "group.com.snapzify.app"
    static let queueFileName = "mediaQueue.json"
    static let maxQueueSize = 100
    static let deepLinkScheme = "snapzify"
}

// MARK: - Shared Queue Manager
@available(iOS 15.0, *)
class ExtensionQueueManager {
    private let logger = Logger(subsystem: "com.snapzify.extension", category: "QueueManager")
    
    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ExtensionConstants.appGroupIdentifier)
    }
    
    // MARK: - Queue Operations
    
    func addToQueue(_ item: QueueItem) throws {
        guard let containerURL = containerURL else {
            throw ExtensionError.containerNotAvailable
        }
        
        let queueFileURL = containerURL.appendingPathComponent(ExtensionConstants.queueFileName)
        
        // Load existing queue
        var queue = loadQueue() ?? []
        
        // Check size limit
        if queue.count >= ExtensionConstants.maxQueueSize {
            // Remove oldest items
            queue.removeFirst(queue.count - ExtensionConstants.maxQueueSize + 1)
        }
        
        // Add new item
        queue.append(item)
        
        // Save queue
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(queue)
        try data.write(to: queueFileURL)
        
        logger.info("Added item to queue. Total items: \(queue.count)")
    }
    
    func loadQueue() -> [QueueItem]? {
        guard let containerURL = containerURL else { return nil }
        
        let queueFileURL = containerURL.appendingPathComponent(ExtensionConstants.queueFileName)
        
        guard let data = try? Data(contentsOf: queueFileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([QueueItem].self, from: data)
    }
    
    func clearQueue() throws {
        guard let containerURL = containerURL else {
            throw ExtensionError.containerNotAvailable
        }
        
        let queueFileURL = containerURL.appendingPathComponent(ExtensionConstants.queueFileName)
        try FileManager.default.removeItem(at: queueFileURL)
        logger.info("Queue cleared")
    }
}

// MARK: - Extension Error Types
enum ExtensionError: LocalizedError {
    case containerNotAvailable
    case unsupportedItemType
    case processingFailed(String)
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .containerNotAvailable:
            return "App group container not available"
        case .unsupportedItemType:
            return "This type of content is not supported"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .saveFailed:
            return "Failed to save to queue"
        }
    }
}

// MARK: - Media Type Detection
struct MediaTypeDetector {
    static func detectType(for item: NSExtensionItem) -> MediaType? {
        guard let attachments = item.attachments else { return nil }
        
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                return .image
            } else if attachment.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                return .video
            }
        }
        
        return nil
    }
    
    enum MediaType {
        case image
        case video
    }
}

// MARK: - Shared UI Components
@available(iOS 15.0, *)
struct ExtensionLoadingView: View {
    let message: String
    let progress: Double?
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(.headline)
            
            if let progress = progress {
                ProgressView(value: progress)
                    .frame(width: 200)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}

@available(iOS 15.0, *)
struct ExtensionSuccessView: View {
    let itemCount: Int
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text(itemCount == 1 ? "Added to Queue" : "\(itemCount) Items Added")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Open Snapzify to process")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: onDismiss) {
                Text("Done")
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(25)
            }
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}

@available(iOS 15.0, *)
struct ExtensionErrorView: View {
    let error: Error
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Text("Retry")
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                    }
                }
                
                Button(action: onDismiss) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.gray)
                        .cornerRadius(25)
                }
            }
        }
        .padding(40)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
    }
}

// MARK: - Deep Link Helper
struct ExtensionDeepLinkHelper {
    static func createProcessingURL(for type: MediaTypeDetector.MediaType, fileName: String) -> URL? {
        var components = URLComponents()
        components.scheme = ExtensionConstants.deepLinkScheme
        components.host = type == .image ? "process-image" : "process-video"
        components.queryItems = [
            URLQueryItem(name: "file", value: fileName)
        ]
        return components.url
    }
    
    static func createQueueURL() -> URL? {
        var components = URLComponents()
        components.scheme = ExtensionConstants.deepLinkScheme
        components.host = "open-queue"
        return components.url
    }
}

// MARK: - Shared Asset Names
// Instead of duplicating assets, reference them from the main app bundle
struct SharedAssets {
    static let actionIcon = "ActionIcon"
    static let appIcon = "AppIcon"
    static let accentColor = "AccentColor"
    
    // Load from main bundle if available, otherwise fall back to extension bundle
    static func image(named name: String) -> UIImage? {
        // Try main bundle first
        if let image = UIImage(named: name, in: Bundle.main, compatibleWith: nil) {
            return image
        }
        
        // Fall back to extension bundle
        return UIImage(named: name)
    }
    
    static func color(named name: String) -> UIColor? {
        // Try main bundle first
        if let color = UIColor(named: name, in: Bundle.main, compatibleWith: nil) {
            return color
        }
        
        // Fall back to extension bundle
        return UIColor(named: name)
    }
}

// MARK: - Logger Extension
@available(iOS 14.0, *)
extension Logger {
    static let extensionLogger = Logger(subsystem: "com.snapzify.extension", category: "General")
    
    func logProcessingStart(type: MediaTypeDetector.MediaType) {
        self.info("Starting \(String(describing: type)) processing")
    }
    
    func logProcessingComplete(itemCount: Int) {
        self.info("Processing complete - \(itemCount) items")
    }
    
    func logProcessingError(_ error: Error) {
        self.error("Processing failed: \(error.localizedDescription)")
    }
}