import Foundation
import Photos
import os.log

struct QueuedMediaItem: Codable {
    let id: UUID
    let assetIdentifier: String?  // PHAsset identifier if from photos
    let mediaData: Data?  // Media data if from share extension
    let isVideo: Bool
    let queuedAt: Date
    let source: DocumentSource
    
    init(assetIdentifier: String? = nil, mediaData: Data? = nil, isVideo: Bool, source: DocumentSource) {
        self.id = UUID()
        self.assetIdentifier = assetIdentifier
        self.mediaData = mediaData
        self.isVideo = isVideo
        self.queuedAt = Date()
        self.source = source
    }
}

@MainActor
class QueuedMediaStore: ObservableObject {
    @Published var queuedItems: [QueuedMediaItem] = []
    @Published var currentQueueIndex: Int?
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "QueuedMediaStore")
    private let queueFileURL: URL
    private let containerURL: URL
    
    init() {
        // Use app group container for sharing between app and extension
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.snapzify.app") else {
            fatalError("Failed to get app group container URL")
        }
        self.containerURL = containerURL
        self.queueFileURL = containerURL.appendingPathComponent("mediaQueue.json")
        
        loadQueue()
    }
    
    func addToQueue(assetIdentifier: String? = nil, mediaData: Data? = nil, isVideo: Bool, source: DocumentSource) {
        let item = QueuedMediaItem(
            assetIdentifier: assetIdentifier,
            mediaData: mediaData,
            isVideo: isVideo,
            source: source
        )
        
        queuedItems.append(item)
        saveQueue()
        
        logger.info("Added item to queue. Total items: \(self.queuedItems.count)")
    }
    
    func addToQueueFromExtension(mediaData: Data, isVideo: Bool) {
        // This method is called from the share extension
        // Save media data to a temporary file in the shared container
        let fileName = "\(UUID().uuidString).\(isVideo ? "mov" : "jpg")"
        let fileURL = containerURL.appendingPathComponent("QueuedMedia").appendingPathComponent(fileName)
        
        do {
            // Create directory if needed
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            // Write media data to file
            try mediaData.write(to: fileURL)
            
            // Add to queue with file URL reference
            let item = QueuedMediaItem(
                assetIdentifier: fileURL.path,  // Store file path in assetIdentifier
                mediaData: nil,  // Don't store data in memory
                isVideo: isVideo,
                source: .shareExtension
            )
            
            var queue = loadQueueFromDisk()
            queue.append(item)
            saveQueueToDisk(queue)
            
            logger.info("Added item from extension to queue")
        } catch {
            logger.error("Failed to save queued media: \(error)")
        }
    }
    
    func getOldestUnprocessed() -> QueuedMediaItem? {
        // Return the oldest item in the queue
        return queuedItems.sorted(by: { $0.queuedAt < $1.queuedAt }).first
    }
    
    func removeFromQueue(_ item: QueuedMediaItem) {
        queuedItems.removeAll { $0.id == item.id }
        
        // Clean up temporary file if it exists
        if item.source == .shareExtension,
           let path = item.assetIdentifier {
            try? FileManager.default.removeItem(atPath: path)
        }
        
        // Adjust current index if needed
        if let currentIndex = currentQueueIndex {
            if currentIndex >= queuedItems.count {
                currentQueueIndex = queuedItems.isEmpty ? nil : queuedItems.count - 1
            }
        }
        
        saveQueue()
        logger.info("Removed item from queue. Remaining: \(self.queuedItems.count)")
    }
    
    func clearQueue() {
        // Clean up all temporary files
        for item in queuedItems {
            if item.source == .shareExtension,
               let path = item.assetIdentifier {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        
        queuedItems.removeAll()
        currentQueueIndex = nil
        saveQueue()
        
        logger.info("Cleared queue")
    }
    
    func moveToNextInQueue() -> QueuedMediaItem? {
        guard !queuedItems.isEmpty else { return nil }
        
        if let currentIndex = currentQueueIndex {
            let nextIndex = currentIndex + 1
            if nextIndex < queuedItems.count {
                currentQueueIndex = nextIndex
                return queuedItems[nextIndex]
            }
        } else {
            // Start at the beginning if no current index
            currentQueueIndex = 0
            return queuedItems.first
        }
        
        return nil
    }
    
    func moveToPreviousInQueue() -> QueuedMediaItem? {
        guard !queuedItems.isEmpty,
              let currentIndex = currentQueueIndex,
              currentIndex > 0 else { return nil }
        
        let previousIndex = currentIndex - 1
        currentQueueIndex = previousIndex
        return queuedItems[previousIndex]
    }
    
    func getCurrentQueueItem() -> QueuedMediaItem? {
        guard let index = currentQueueIndex,
              index < queuedItems.count else { return nil }
        return queuedItems[index]
    }
    
    // MARK: - Private Methods
    
    private func loadQueue() {
        queuedItems = loadQueueFromDisk()
        
        // Clean up any orphaned temporary files
        cleanupOrphanedFiles()
    }
    
    private func loadQueueFromDisk() -> [QueuedMediaItem] {
        guard FileManager.default.fileExists(atPath: queueFileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: queueFileURL)
            let items = try JSONDecoder().decode([QueuedMediaItem].self, from: data)
            logger.info("Loaded \(items.count) items from queue")
            return items
        } catch {
            logger.error("Failed to load queue: \(error)")
            return []
        }
    }
    
    private func saveQueue() {
        saveQueueToDisk(queuedItems)
    }
    
    private func saveQueueToDisk(_ items: [QueuedMediaItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: queueFileURL)
            logger.info("Saved \(items.count) items to queue")
        } catch {
            logger.error("Failed to save queue: \(error)")
        }
    }
    
    private func cleanupOrphanedFiles() {
        let queuedMediaDir = containerURL.appendingPathComponent("QueuedMedia")
        guard FileManager.default.fileExists(atPath: queuedMediaDir.path) else { return }
        
        // Get all files in the directory
        if let files = try? FileManager.default.contentsOfDirectory(at: queuedMediaDir, includingPropertiesForKeys: nil) {
            let validPaths = Set(queuedItems.compactMap { $0.assetIdentifier })
            
            for file in files {
                if !validPaths.contains(file.path) {
                    // This file is not referenced by any queue item
                    try? FileManager.default.removeItem(at: file)
                    logger.info("Cleaned up orphaned file: \(file.lastPathComponent)")
                }
            }
        }
    }
}