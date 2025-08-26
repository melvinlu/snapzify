import Foundation
import UIKit
import AVFoundation

// MARK: - Base Service Protocol
/// Base protocol for all services
protocol Service: AnyObject {
    var isConfigured: Bool { get }
    func configure() async throws
    func reset()
}

// MARK: - OCR Service Protocol
protocol OCRServiceProtocol: Service {
    func recognizeText(in image: UIImage) async throws -> [OCRLine]
    func recognizeText(in images: [UIImage]) async throws -> [[OCRLine]]
    func recognizeText(in videoFrame: CVPixelBuffer) async throws -> [OCRLine]
}

// MARK: - Translation Service Protocol
protocol TranslationServiceProtocol: Service {
    func translate(_ text: String, from: String, to: String) async throws -> String
    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String]
    var supportedLanguages: Set<String> { get }
}

// MARK: - Text-to-Speech Service Protocol
protocol TTSServiceProtocol: Service {
    func generateAudio(for text: String, language: String) async throws -> AudioAsset
    func generateAudioBatch(texts: [(id: UUID, text: String)], language: String) async throws -> [UUID: AudioAsset]
    func playAudio(_ asset: AudioAsset) async throws
    func stopAudio()
    var isPlaying: Bool { get }
}

// MARK: - Chinese Processing Protocol
protocol ChineseProcessingProtocol: Service {
    func process(_ text: String, script: ChineseScript) async throws -> ChineseProcessingResult
    func processBatch(_ texts: [String], script: ChineseScript) async throws -> [ChineseProcessingResult]
    func convertScript(text: String, from: ChineseScript, to: ChineseScript) async throws -> String
}

struct ChineseProcessingResult {
    let text: String
    let pinyin: [String]
    let english: String?
    let tokens: [Token]
}

// MARK: - Streaming Service Protocol
protocol StreamingServiceProtocol: Service {
    associatedtype StreamType
    func stream(_ input: StreamType) -> AsyncThrowingStream<String, Error>
}

// MARK: - Storage Service Protocol
protocol StorageServiceProtocol: Service {
    associatedtype StoredType: Codable
    
    func save(_ item: StoredType) async throws
    func fetch(id: UUID) async throws -> StoredType?
    func fetchAll() async throws -> [StoredType]
    func delete(id: UUID) async throws
    func update(_ item: StoredType) async throws
    func exists(id: UUID) async -> Bool
}

// MARK: - Cache Service Protocol
protocol CacheServiceProtocol: Service {
    associatedtype CachedType
    associatedtype KeyType: Hashable
    
    func get(_ key: KeyType) -> CachedType?
    func set(_ key: KeyType, value: CachedType, cost: Int?)
    func remove(_ key: KeyType)
    func clear()
    var currentSize: Int { get }
    var maxSize: Int { get }
}

// MARK: - Media Processing Protocol
protocol MediaProcessingProtocol: Service {
    func processImage(_ image: UIImage, options: ProcessingOptions) async throws -> ProcessedMedia
    func processVideo(at url: URL, options: ProcessingOptions) async throws -> ProcessedMedia
    func generateThumbnail(from: MediaSource) async throws -> UIImage
}

struct ProcessingOptions {
    let script: ChineseScript
    let source: DocumentSource
    let quality: ProcessingQuality
    let enableOCR: Bool
    let enableTranslation: Bool
    
    enum ProcessingQuality {
        case draft
        case standard
        case high
    }
}

struct ProcessedMedia {
    let id: UUID
    let mediaURL: URL
    let thumbnailURL: URL?
    let sentences: [Sentence]
    let metadata: MediaMetadata
}

struct MediaMetadata {
    let width: Int
    let height: Int
    let duration: TimeInterval?
    let frameRate: Double?
    let fileSize: Int64
}

enum MediaSource {
    case image(UIImage)
    case imageURL(URL)
    case video(URL)
}

// MARK: - Network Service Protocol
protocol NetworkServiceProtocol: Service {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    func upload<T: Decodable>(_ endpoint: Endpoint, data: Data) async throws -> T
    func download(_ endpoint: Endpoint) async throws -> Data
    func stream(_ endpoint: Endpoint) -> AsyncThrowingStream<Data, Error>
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]?
    let queryItems: [URLQueryItem]?
    let body: Data?
    let timeout: TimeInterval
    
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"
    }
}

// MARK: - Configuration Protocol
protocol ConfigurableService: Service {
    associatedtype Configuration
    func configure(with configuration: Configuration) async throws
    var currentConfiguration: Configuration? { get }
}

// MARK: - Observable Service Protocol
protocol ObservableService: Service, ObservableObject {
    associatedtype StateType
    var state: StateType { get }
}

// MARK: - Service Lifecycle Protocol
protocol ServiceLifecycle {
    func start() async throws
    func stop() async
    func pause() async
    func resume() async
    var isRunning: Bool { get }
}

// MARK: - Error Handling Protocol
protocol ServiceErrorHandler {
    func handleError(_ error: Error) async
    func canRecover(from error: Error) -> Bool
    func attemptRecovery(from error: Error) async throws
}

// MARK: - Service Factory Protocol
protocol ServiceFactory {
    associatedtype ServiceType
    func createService() -> ServiceType
    func createMockService() -> ServiceType
}

// MARK: - Service Container Protocol
protocol ServiceContainerProtocol {
    func register<T>(_ service: T, for type: T.Type)
    func resolve<T>(_ type: T.Type) -> T?
    func reset()
}

// MARK: - Default Implementations
extension Service {
    var isConfigured: Bool { true }
    func configure() async throws {}
    func reset() {}
}

extension CacheServiceProtocol {
    func set(_ key: KeyType, value: CachedType) {
        set(key, value: value, cost: nil)
    }
}

extension ServiceErrorHandler {
    func canRecover(from error: Error) -> Bool {
        // Default implementation
        if let snapzifyError = error as? SnapzifyError {
            return snapzifyError.isRecoverable
        }
        return false
    }
}