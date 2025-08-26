import Foundation

class DocumentStoreImpl: DocumentStore {
    private let fileManager = FileManager.default
    private var documentsDirectory: URL? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) else { return nil }
        
        return containerURL.appendingPathComponent("Documents")
    }
    
    init() {
        createDirectoryIfNeeded()
    }
    
    private func createDirectoryIfNeeded() {
        guard let dir = documentsDirectory else { return }
        
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    func save(_ document: Document) async throws {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let fileURL = dir.appendingPathComponent("\(document.id.uuidString).json")
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL)
        
        // Also save metadata cache
        let metadataURL = dir.appendingPathComponent("\(document.id.uuidString).meta")
        let metadata = DocumentMetadata(from: document)
        if let metaData = try? JSONEncoder().encode(metadata) {
            try? metaData.write(to: metadataURL)
        }
    }
    
    func fetchAll() async throws -> [Document] {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        
        var documents: [Document] = []
        
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let document = try? JSONDecoder().decode(Document.self, from: data) {
                documents.append(document)
            }
        }
        
        return documents.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetch(id: UUID) async throws -> Document? {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let fileURL = dir.appendingPathComponent("\(id.uuidString).json")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Document.self, from: data)
    }
    
    func delete(id: UUID) async throws {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let fileURL = dir.appendingPathComponent("\(id.uuidString).json")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    func fetchLatest() async throws -> Document? {
        let all = try await fetchAll()
        return all.first
    }
    
    func deleteAll() async throws {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        
        for file in files where file.pathExtension == "json" {
            try fileManager.removeItem(at: file)
        }
    }
    
    func update(_ document: Document) async throws {
        try await save(document)
    }
    
    func fetchRecent(limit: Int) async throws -> [Document] {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
            .prefix(limit)
        
        var documents: [Document] = []
        for file in files {
            let data = try Data(contentsOf: file)
            let document = try JSONDecoder().decode(Document.self, from: data)
            documents.append(document)
        }
        
        return documents.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetchSaved() async throws -> [Document] {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        // Get files sorted by modification date, most recent first
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
        
        var savedDocuments: [Document] = []
        var checkedCount = 0
        let maxToCheck = 100  // Only check the most recent 100 files for saved documents
        
        for file in files {
            if checkedCount >= maxToCheck || savedDocuments.count >= 20 {
                break  // Stop if we've checked enough files or found enough saved docs
            }
            
            let data = try Data(contentsOf: file)
            let document = try JSONDecoder().decode(Document.self, from: data)
            if document.isSaved {
                savedDocuments.append(document)
            }
            checkedCount += 1
        }
        
        return savedDocuments.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetchRecentMetadata(limit: Int) async throws -> [DocumentMetadata] {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
            .prefix(limit)
        
        var metadata: [DocumentMetadata] = []
        for file in files {
            // Try to load cached metadata first
            let metadataFile = file.deletingPathExtension().appendingPathExtension("meta")
            if let metaData = try? Data(contentsOf: metadataFile),
               let meta = try? JSONDecoder().decode(DocumentMetadata.self, from: metaData) {
                metadata.append(meta)
            } else {
                // Fall back to loading full document if no metadata cache
                let data = try Data(contentsOf: file)
                if let doc = try? JSONDecoder().decode(Document.self, from: data) {
                    let meta = DocumentMetadata(from: doc)
                    metadata.append(meta)
                    // Cache the metadata for next time
                    if let metaData = try? JSONEncoder().encode(meta) {
                        try? metaData.write(to: metadataFile)
                    }
                }
            }
        }
        
        return metadata.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetchSavedMetadata() async throws -> [DocumentMetadata] {
        guard let dir = documentsDirectory else {
            throw StoreError.noDirectory
        }
        
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
        
        var savedMetadata: [DocumentMetadata] = []
        var checkedCount = 0
        let maxToCheck = 100
        
        for file in files {
            if checkedCount >= maxToCheck || savedMetadata.count >= 20 {
                break
            }
            
            // Try to load cached metadata first
            let metadataFile = file.deletingPathExtension().appendingPathExtension("meta")
            var meta: DocumentMetadata?
            
            if let metaData = try? Data(contentsOf: metadataFile) {
                meta = try? JSONDecoder().decode(DocumentMetadata.self, from: metaData)
            }
            
            // Fall back to loading full document if no metadata cache
            if meta == nil {
                let data = try Data(contentsOf: file)
                if let doc = try? JSONDecoder().decode(Document.self, from: data) {
                    meta = DocumentMetadata(from: doc)
                    // Cache the metadata for next time
                    if let metaData = try? JSONEncoder().encode(meta!) {
                        try? metaData.write(to: metadataFile)
                    }
                }
            }
            
            if let meta = meta, meta.isSaved {
                savedMetadata.append(meta)
            }
            checkedCount += 1
        }
        
        return savedMetadata.sorted { $0.createdAt > $1.createdAt }
    }
}

enum StoreError: Error {
    case noDirectory
}