import Foundation

// MARK: - Protocol
protocol DocumentService {
    func save(_ document: Document) async throws
    func load(_ id: UUID) async throws -> Document?
    func delete(_ id: UUID) async throws
    func list() async throws -> [Document]
    func update(_ document: Document) async throws
}

// MARK: - Implementation
class DocumentServiceImpl: DocumentService {
    private let store: DocumentStore
    
    init(store: DocumentStore) {
        self.store = store
    }
    
    func save(_ document: Document) async throws {
        try await store.save(document)
    }
    
    func load(_ id: UUID) async throws -> Document? {
        return try await store.fetch(id: id)
    }
    
    func delete(_ id: UUID) async throws {
        try await store.delete(id: id)
    }
    
    func list() async throws -> [Document] {
        return try await store.fetchAll()
    }
    
    func update(_ document: Document) async throws {
        try await store.update(document)
    }
}