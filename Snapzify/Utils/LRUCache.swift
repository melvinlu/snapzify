import Foundation
import UIKit

// MARK: - LRU Cache Implementation
/// Thread-safe Least Recently Used cache with size limits
final class LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let key: Key
        let value: Value
        let size: Int
        var lastAccessTime: Date
    }
    
    private var cache: [Key: CacheEntry] = [:]
    private let maxSize: Int
    private let maxCount: Int
    private var currentSize: Int = 0
    private let queue = DispatchQueue(label: "com.snapzify.lrucache", attributes: .concurrent)
    
    init(maxSize: Int = 100_000_000, maxCount: Int = 100) { // 100MB default
        self.maxSize = maxSize
        self.maxCount = maxCount
    }
    
    func get(_ key: Key) -> Value? {
        queue.sync(flags: .barrier) {
            if var entry = cache[key] {
                entry.lastAccessTime = Date()
                cache[key] = entry
                return entry.value
            }
            return nil
        }
    }
    
    func set(_ key: Key, value: Value, size: Int) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // Remove existing entry if present
            if let existingEntry = self.cache[key] {
                self.currentSize -= existingEntry.size
            }
            
            // Add new entry
            let entry = CacheEntry(key: key, value: value, size: size, lastAccessTime: Date())
            self.cache[key] = entry
            self.currentSize += size
            
            // Evict if necessary
            self.evictIfNeeded()
        }
    }
    
    func remove(_ key: Key) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let entry = self.cache.removeValue(forKey: key) {
                self.currentSize -= entry.size
            }
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
            self?.currentSize = 0
        }
    }
    
    private func evictIfNeeded() {
        // Check count limit
        while cache.count > maxCount {
            evictOldest()
        }
        
        // Check size limit
        while currentSize > maxSize && !cache.isEmpty {
            evictOldest()
        }
    }
    
    private func evictOldest() {
        guard let oldestEntry = cache.values.min(by: { $0.lastAccessTime < $1.lastAccessTime }) else {
            return
        }
        
        cache.removeValue(forKey: oldestEntry.key)
        currentSize -= oldestEntry.size
    }
    
    var debugDescription: String {
        queue.sync {
            "LRUCache: \(cache.count) items, \(currentSize / 1_000_000)MB / \(maxSize / 1_000_000)MB"
        }
    }
}

// MARK: - Document Cache Manager
/// Manages caching of documents with automatic memory management
class DocumentCacheManager {
    static let shared = DocumentCacheManager()
    
    private let imageCache = LRUCache<UUID, UIImage>(maxSize: 50_000_000, maxCount: 20) // 50MB for images
    private let documentCache = LRUCache<UUID, Document>(maxSize: 20_000_000, maxCount: 30) // 20MB for documents
    private let thumbnailCache = LRUCache<UUID, UIImage>(maxSize: 10_000_000, maxCount: 100) // 10MB for thumbnails
    
    private init() {}
    
    // MARK: - Image Cache
    
    func getCachedImage(for documentId: UUID) -> UIImage? {
        return imageCache.get(documentId)
    }
    
    func cacheImage(_ image: UIImage, for documentId: UUID) {
        let size = Int(image.size.width * image.size.height * 4) // Approximate size in bytes
        imageCache.set(documentId, value: image, size: size)
    }
    
    // MARK: - Document Cache
    
    func getCachedDocument(_ id: UUID) -> Document? {
        return documentCache.get(id)
    }
    
    func cacheDocument(_ document: Document) {
        // Estimate document size (rough approximation)
        let jsonEncoder = JSONEncoder()
        if let data = try? jsonEncoder.encode(document) {
            documentCache.set(document.id, value: document, size: data.count)
        }
    }
    
    func removeCachedDocument(_ id: UUID) {
        documentCache.remove(id)
        imageCache.remove(id)
        thumbnailCache.remove(id)
    }
    
    // MARK: - Thumbnail Cache
    
    func getCachedThumbnail(for documentId: UUID) -> UIImage? {
        return thumbnailCache.get(documentId)
    }
    
    func cacheThumbnail(_ thumbnail: UIImage, for documentId: UUID) {
        let size = Int(thumbnail.size.width * thumbnail.size.height * 4)
        thumbnailCache.set(documentId, value: thumbnail, size: size)
    }
    
    // MARK: - Memory Management
    
    func clearAllCaches() {
        imageCache.clear()
        documentCache.clear()
        thumbnailCache.clear()
    }
    
    func handleMemoryWarning() {
        // Clear image cache first (largest items)
        imageCache.clear()
        // Keep documents and thumbnails if possible
    }
    
    var debugDescription: String {
        """
        DocumentCacheManager:
        - Images: \(imageCache.debugDescription)
        - Documents: \(documentCache.debugDescription)
        - Thumbnails: \(thumbnailCache.debugDescription)
        """
    }
}

// MARK: - Memory Monitor
/// Monitors memory usage and triggers cache cleanup when needed
class MemoryMonitor {
    static let shared = MemoryMonitor()
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    @objc private func handleMemoryWarning() {
        print("⚠️ Memory warning received, clearing caches...")
        DocumentCacheManager.shared.handleMemoryWarning()
        MediaStorageService.shared.clearOldCache(olderThan: 1)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}