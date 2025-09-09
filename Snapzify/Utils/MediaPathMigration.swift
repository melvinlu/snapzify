import Foundation

/// Handles migration of media paths to be relative instead of absolute
/// This ensures media files remain accessible after app reinstalls/updates
@MainActor
class MediaPathMigration {
    static let shared = MediaPathMigration()
    
    private let fileManager = FileManager.default
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    private init() {}
    
    /// Migrate a document's media URLs from absolute to relative paths
    func migrateDocument(_ document: Document) -> Document {
        var migratedDocument = document
        
        // Migrate mediaURL
        if let mediaURL = document.mediaURL {
            migratedDocument.mediaURL = migrateURL(mediaURL)
        }
        
        // Migrate thumbnailURL
        if let thumbnailURL = document.thumbnailURL {
            migratedDocument.thumbnailURL = migrateURL(thumbnailURL)
        }
        
        return migratedDocument
    }
    
    /// Convert an absolute URL to a relative path or resolve it to the current documents directory
    private func migrateURL(_ url: URL) -> URL? {
        let path = url.path
        
        // Check if file exists at the original URL
        if fileManager.fileExists(atPath: path) {
            return url
        }
        
        // Extract just the filename and subdirectory structure
        let filename = url.lastPathComponent
        let pathComponents = url.pathComponents
        
        // Look for Media or Thumbnails directory in the path
        if let mediaIndex = pathComponents.firstIndex(of: "Media") {
            // Reconstruct path from Media directory onwards
            let relativeComponents = Array(pathComponents[mediaIndex...])
            var newURL = documentsDirectory
            for component in relativeComponents {
                newURL.appendPathComponent(component)
            }
            
            // Check if file exists at new location
            if fileManager.fileExists(atPath: newURL.path) {
                return newURL
            }
        } else if let thumbIndex = pathComponents.firstIndex(of: "Thumbnails") {
            // Reconstruct path from Thumbnails directory onwards
            let relativeComponents = Array(pathComponents[thumbIndex...])
            var newURL = documentsDirectory
            for component in relativeComponents {
                newURL.appendPathComponent(component)
            }
            
            // Check if file exists at new location
            if fileManager.fileExists(atPath: newURL.path) {
                return newURL
            }
        }
        
        // Last resort: try to find the file in Media or Thumbnails directories
        let mediaDir = documentsDirectory.appendingPathComponent("Media")
        let thumbDir = documentsDirectory.appendingPathComponent("Thumbnails")
        
        let mediaPath = mediaDir.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: mediaPath.path) {
            return mediaPath
        }
        
        let thumbPath = thumbDir.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: thumbPath.path) {
            return thumbPath
        }
        
        // File not found - return nil to indicate missing media
        return nil
    }
    
    /// Check if a URL needs migration
    func needsMigration(_ url: URL) -> Bool {
        return !fileManager.fileExists(atPath: url.path)
    }
    
    /// Migrate all documents in the store
    func migrateAllDocuments(in documents: [Document]) -> [Document] {
        return documents.map { document in
            var needsMigration = false
            
            if let mediaURL = document.mediaURL, self.needsMigration(mediaURL) {
                needsMigration = true
            }
            
            if let thumbnailURL = document.thumbnailURL, self.needsMigration(thumbnailURL) {
                needsMigration = true
            }
            
            return needsMigration ? migrateDocument(document) : document
        }
    }
}