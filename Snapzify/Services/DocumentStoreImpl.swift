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
    
    func fetchSaved() async throws -> [Document] {
        let all = try await fetchAll()
        return all.filter { $0.isSaved }
    }
}

enum StoreError: Error {
    case noDirectory
}