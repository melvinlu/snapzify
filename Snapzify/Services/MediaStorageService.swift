import Foundation
import UIKit
import CoreGraphics

// MARK: - Media Storage Service
/// Handles efficient file-based storage for media content
@MainActor
class MediaStorageService {
    static let shared = MediaStorageService()
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let mediaDirectory: URL
    private let thumbnailDirectory: URL
    private let cacheDirectory: URL
    
    private init() {
        // Setup directory structure
        documentsDirectory = fileManager.urls(for: .documentDirectory, 
                                             in: .userDomainMask).first!
        mediaDirectory = documentsDirectory.appendingPathComponent("Media")
        thumbnailDirectory = documentsDirectory.appendingPathComponent("Thumbnails")
        cacheDirectory = fileManager.urls(for: .cachesDirectory, 
                                         in: .userDomainMask).first!
            .appendingPathComponent("MediaCache")
        
        // Create directories if they don't exist
        createDirectoriesIfNeeded()
    }
    
    private func createDirectoriesIfNeeded() {
        let directories = [mediaDirectory, thumbnailDirectory, cacheDirectory]
        for directory in directories {
            try? fileManager.createDirectory(at: directory, 
                                            withIntermediateDirectories: true, 
                                            attributes: nil)
        }
    }
    
    // MARK: - Media Storage
    
    /// Save media data to disk and return the file URL
    func saveMedia(_ data: Data, id: UUID, isVideo: Bool) throws -> URL {
        let extension = isVideo ? "mov" : "jpg"
        let filename = "\(id.uuidString).\(extension)"
        let fileURL = mediaDirectory.appendingPathComponent(filename)
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    /// Save thumbnail and return the file URL
    func saveThumbnail(_ image: UIImage, id: UUID) throws -> URL {
        let filename = "\(id.uuidString)_thumb.jpg"
        let fileURL = thumbnailDirectory.appendingPathComponent(filename)
        
        guard let data = image.jpegData(compressionQuality: 0.7) else {
            throw MediaStorageError.thumbnailCreationFailed
        }
        
        try data.write(to: fileURL)
        return fileURL
    }
    
    /// Generate thumbnail from media
    func generateThumbnail(from imageData: Data, targetSize: CGSize = CGSize(width: 120, height: 120)) -> UIImage? {
        guard let image = UIImage(data: imageData) else { return nil }
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// Load media data from URL
    func loadMedia(from url: URL) throws -> Data {
        return try Data(contentsOf: url)
    }
    
    /// Delete media files for document
    func deleteMediaFiles(for documentId: UUID) {
        let extensions = ["jpg", "mov", "_thumb.jpg"]
        for ext in extensions {
            let filename = "\(documentId.uuidString).\(ext)"
            let fileURL = mediaDirectory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: fileURL)
            
            let thumbURL = thumbnailDirectory.appendingPathComponent(filename)
            try? fileManager.removeItem(at: thumbURL)
        }
    }
    
    /// Get cache size
    func getCacheSize() -> Int64 {
        var size: Int64 = 0
        
        let directories = [mediaDirectory, thumbnailDirectory, cacheDirectory]
        for directory in directories {
            if let enumerator = fileManager.enumerator(at: directory,
                                                      includingPropertiesForKeys: [.fileSizeKey]) {
                for case let url as URL in enumerator {
                    if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        size += Int64(fileSize)
                    }
                }
            }
        }
        
        return size
    }
    
    /// Clear old cache files
    func clearOldCache(olderThan days: Int = 7) {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))
        
        if let enumerator = fileManager.enumerator(at: cacheDirectory,
                                                  includingPropertiesForKeys: [.creationDateKey]) {
            for case let url as URL in enumerator {
                if let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }
}

// MARK: - Errors
enum MediaStorageError: LocalizedError {
    case thumbnailCreationFailed
    case mediaNotFound
    case saveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .thumbnailCreationFailed:
            return "Failed to create thumbnail"
        case .mediaNotFound:
            return "Media file not found"
        case .saveFailed(let error):
            return "Failed to save media: \(error.localizedDescription)"
        }
    }
}