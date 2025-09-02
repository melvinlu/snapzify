import Foundation

// Shared queue item structure used by both the app and extensions
public struct QueueItem: Codable {
    public let id: String
    public let fileName: String
    public let isVideo: Bool
    public let queuedAt: Date
    public let source: String
    
    public init(id: String, fileName: String, isVideo: Bool, queuedAt: Date, source: String) {
        self.id = id
        self.fileName = fileName
        self.isVideo = isVideo
        self.queuedAt = queuedAt
        self.source = source
    }
}