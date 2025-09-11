import Foundation
import UIKit
import os.log

// MARK: - Document Cache Manager
/// Manages in-memory caching of documents with automatic eviction and memory pressure handling
@MainActor
final class DocumentCacheManager: ObservableObject {
    static let shared = DocumentCacheManager()
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "DocumentCache")
    
    // Cache storage
    private var documentCache: LRUCache<UUID, Document>
    private var thumbnailCache: LRUCache<UUID, UIImage>
    private var metadataCache: LRUCache<UUID, DocumentMetadata>
    
    // Memory monitoring
    private var memoryWarningObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    
    // Cache statistics
    @Published var cacheHits: Int = 0
    @Published var cacheMisses: Int = 0
    @Published var currentMemoryUsage: Int = 0
    @Published var evictionCount: Int = 0
    
    // Configuration
    private let maxDocumentCacheSize: Int
    private let maxThumbnailCacheSize: Int
    private let maxMetadataCacheSize: Int
    
    private init() {
        // Initialize caches with size limits from Constants
        self.maxDocumentCacheSize = Constants.Cache.maxDocumentCacheSize
        self.maxThumbnailCacheSize = Constants.Cache.maxThumbnailCacheSize
        let metadataCacheSize = 5_000_000 // 5MB for metadata
        self.maxMetadataCacheSize = metadataCacheSize
        
        self.documentCache = LRUCache(
            maxSize: maxDocumentCacheSize,
            maxCount: Constants.Cache.maxDocumentCacheCount
        )
        
        self.thumbnailCache = LRUCache(
            maxSize: maxThumbnailCacheSize,
            maxCount: Constants.Cache.maxThumbnailCacheCount
        )
        
        self.metadataCache = LRUCache(
            maxSize: metadataCacheSize,
            maxCount: 100
        )
        
        setupMemoryMonitoring()
        logger.info("DocumentCacheManager initialized with limits - Documents: \(self.maxDocumentCacheSize) bytes, Thumbnails: \(self.maxThumbnailCacheSize) bytes")
    }
    
    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Document Caching
    
    /// Cache a document
    func cache(_ document: Document) {
        let size = estimateDocumentSize(document)
        documentCache.set(document, forKey: document.id, size: size)
        updateMemoryUsage()
        logger.debug("Cached document \(document.id) - size: \(size) bytes")
    }
    
    /// Retrieve a cached document
    func getDocument(_ id: UUID) -> Document? {
        if let document = documentCache.get(id) {
            cacheHits += 1
            logger.debug("Cache hit for document \(id)")
            return document
        } else {
            cacheMisses += 1
            logger.debug("Cache miss for document \(id)")
            return nil
        }
    }
    
    /// Remove a document from cache
    func removeDocument(_ id: UUID) {
        documentCache.remove(id)
        thumbnailCache.remove(id)
        metadataCache.remove(id)
        updateMemoryUsage()
        logger.debug("Removed document \(id) from cache")
    }
    
    /// Cache multiple documents efficiently
    func cacheDocuments(_ documents: [Document]) {
        for document in documents {
            // Only cache if not already present
            if documentCache.get(document.id) == nil {
                cache(document)
            }
        }
    }
    
    // MARK: - Thumbnail Caching
    
    /// Cache a thumbnail
    func cacheThumbnail(_ image: UIImage, for documentId: UUID) {
        let size = estimateImageSize(image)
        thumbnailCache.set(image, forKey: documentId, size: size)
        updateMemoryUsage()
        logger.debug("Cached thumbnail for document \(documentId) - size: \(size) bytes")
    }
    
    /// Retrieve a cached thumbnail
    func getThumbnail(for documentId: UUID) -> UIImage? {
        if let thumbnail = thumbnailCache.get(documentId) {
            cacheHits += 1
            return thumbnail
        } else {
            cacheMisses += 1
            return nil
        }
    }
    
    // MARK: - Metadata Caching
    
    /// Cache document metadata (lighter weight than full document)
    func cacheMetadata(_ metadata: DocumentMetadata) {
        let size = estimateMetadataSize(metadata)
        metadataCache.set(metadata, forKey: metadata.id, size: size)
        updateMemoryUsage()
    }
    
    /// Retrieve cached metadata
    func getMetadata(_ id: UUID) -> DocumentMetadata? {
        return metadataCache.get(id)
    }
    
    // MARK: - Cache Management
    
    /// Clear all caches
    func clearAll() {
        documentCache.clear()
        thumbnailCache.clear()
        metadataCache.clear()
        evictionCount = 0
        cacheHits = 0
        cacheMisses = 0
        updateMemoryUsage()
        logger.info("All caches cleared")
    }
    
    /// Clear caches older than specified date
    func clearOlderThan(_ date: Date) {
        // This would require tracking access times in the cache
        // For now, we'll clear based on a percentage
        let percentToClear = 0.3 // Clear 30% of oldest items
        
        let documentsToRemove = Int(Double(documentCache.count) * percentToClear)
        let thumbnailsToRemove = Int(Double(thumbnailCache.count) * percentToClear)
        
        documentCache.evictOldest(count: documentsToRemove)
        thumbnailCache.evictOldest(count: thumbnailsToRemove)
        
        evictionCount += documentsToRemove + thumbnailsToRemove
        updateMemoryUsage()
        logger.info("Cleared \(documentsToRemove) documents and \(thumbnailsToRemove) thumbnails")
    }
    
    /// Preload documents for improved performance
    func preloadDocuments(_ ids: [UUID]) async {
        // This would typically load from disk/network
        // For now, we'll just log the intent
        logger.info("Preloading \(ids.count) documents")
        
        // In a real implementation, you would:
        // 1. Check which documents aren't cached
        // 2. Load them from storage
        // 3. Cache them
    }
    
    // MARK: - Memory Management
    
    private func setupMemoryMonitoring() {
        // Monitor memory warnings
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        
        // Monitor app backgrounding
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleEnterBackground()
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("Received memory warning - clearing caches")
        
        // Progressive cache clearing based on priority
        // 1. Clear thumbnails first (can be regenerated)
        let thumbnailsCleared = thumbnailCache.count
        thumbnailCache.clear()
        
        // 2. Clear metadata (small, but numerous)
        let metadataCleared = metadataCache.count
        metadataCache.clear()
        
        // 3. Clear 50% of documents if still under pressure
        let documentsToEvict = documentCache.count / 2
        documentCache.evictOldest(count: documentsToEvict)
        
        evictionCount += thumbnailsCleared + metadataCleared + documentsToEvict
        updateMemoryUsage()
        
        logger.info("Memory warning handled - cleared \(thumbnailsCleared) thumbnails, \(metadataCleared) metadata, \(documentsToEvict) documents")
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: Notification.Name(Constants.NotificationName.memoryWarning),
            object: nil
        )
    }
    
    private func handleEnterBackground() {
        logger.info("App entering background - reducing cache size")
        
        // Keep only essential items in cache
        let documentsToKeep = min(5, documentCache.count)
        let thumbnailsToKeep = min(10, thumbnailCache.count)
        
        if documentCache.count > documentsToKeep {
            documentCache.evictOldest(count: documentCache.count - documentsToKeep)
        }
        
        if thumbnailCache.count > thumbnailsToKeep {
            thumbnailCache.evictOldest(count: thumbnailCache.count - thumbnailsToKeep)
        }
        
        updateMemoryUsage()
    }
    
    // MARK: - Size Estimation
    
    private func estimateDocumentSize(_ document: Document) -> Int {
        var size = 0
        
        // Estimate based on document properties
        size += document.sentences.count * 200 // Approximate bytes per sentence
        size += (document.customName ?? "").count * 2 // Unicode characters
        
        // Add media reference size (not actual media data)
        if document.mediaURL != nil {
            size += 100 // URL reference
        }
        
        if document.thumbnailURL != nil {
            size += 100 // URL reference
        }
        
        return size
    }
    
    private func estimateImageSize(_ image: UIImage) -> Int {
        // Estimate based on dimensions and bytes per pixel
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return width * height * 4 // 4 bytes per pixel (RGBA)
    }
    
    private func estimateMetadataSize(_ metadata: DocumentMetadata) -> Int {
        // Rough estimate for metadata
        return 500 // Base size for metadata structure
    }
    
    private func updateMemoryUsage() {
        currentMemoryUsage = documentCache.currentSize + thumbnailCache.currentSize + metadataCache.currentSize
        logger.debug("Current memory usage: \(currentMemoryUsage) bytes")
    }
    
    // MARK: - Cache Statistics
    
    func getCacheStatistics() -> CacheStatistics {
        CacheStatistics(
            documentCount: documentCache.count,
            thumbnailCount: thumbnailCache.count,
            metadataCount: metadataCache.count,
            totalMemoryUsage: currentMemoryUsage,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            hitRate: cacheHits > 0 ? Double(cacheHits) / Double(cacheHits + cacheMisses) : 0,
            evictionCount: evictionCount
        )
    }
    
    /// Warm up cache with frequently accessed documents
    func warmUpCache(with documentIds: [UUID]) async {
        logger.info("Warming up cache with \(documentIds.count) documents")
        await preloadDocuments(documentIds)
    }
}

// MARK: - Cache Statistics
struct CacheStatistics {
    let documentCount: Int
    let thumbnailCount: Int
    let metadataCount: Int
    let totalMemoryUsage: Int
    let cacheHits: Int
    let cacheMisses: Int
    let hitRate: Double
    let evictionCount: Int
    
    var formattedMemoryUsage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(totalMemoryUsage))
    }
    
    var formattedHitRate: String {
        String(format: "%.1f%%", hitRate * 100)
    }
}

// MARK: - Document Metadata
/// Lightweight representation of a document for caching
struct DocumentMetadata: Codable {
    let id: UUID
    let createdDate: Date
    let modifiedDate: Date
    let customName: String?
    let sentenceCount: Int
    let isSaved: Bool
    let thumbnailURL: URL?
    let script: ChineseScript
    
    init(from document: Document) {
        self.id = document.id
        self.createdDate = document.createdDate
        self.modifiedDate = document.modifiedDate
        self.customName = document.customName
        self.sentenceCount = document.sentences.count
        self.isSaved = document.isSaved
        self.thumbnailURL = document.thumbnailURL
        self.script = document.script
    }
}