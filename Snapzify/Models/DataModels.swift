import Foundation
import CoreGraphics

enum ChineseScript: String, Codable, CaseIterable, Hashable {
    case simplified
    case traditional
}

enum DocumentSource: String, Codable, Hashable {
    case shareExtension
    case photos
    case imported
}

enum SentenceStatus: Codable, Equatable, Hashable {
    case pending
    case ocrOnly
    case translated
    case error(String)
    
    enum CodingKeys: CodingKey {
        case type
        case errorMessage
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "pending":
            self = .pending
        case "ocrOnly":
            self = .ocrOnly
        case "translated":
            self = .translated
        case "error":
            let message = try container.decode(String.self, forKey: .errorMessage)
            self = .error(message)
        default:
            self = .pending
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending:
            try container.encode("pending", forKey: .type)
        case .ocrOnly:
            try container.encode("ocrOnly", forKey: .type)
        case .translated:
            try container.encode("translated", forKey: .type)
        case .error(let message):
            try container.encode("error", forKey: .type)
            try container.encode(message, forKey: .errorMessage)
        }
    }
}

struct Document: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let source: DocumentSource
    var script: ChineseScript
    var sentences: [Sentence]
    var imageData: Data?
    var videoData: Data?  // Store video data for playback
    var isVideo: Bool
    var isSaved: Bool
    var assetIdentifier: String?  // PHAsset localIdentifier for photo library deletion
    
    init(id: UUID = UUID(), createdAt: Date = Date(), source: DocumentSource, script: ChineseScript = .simplified, sentences: [Sentence] = [], imageData: Data? = nil, videoData: Data? = nil, isVideo: Bool = false, isSaved: Bool = false, assetIdentifier: String? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.script = script
        self.sentences = sentences
        self.imageData = imageData
        self.videoData = videoData
        self.isVideo = isVideo
        self.isSaved = isSaved
        self.assetIdentifier = assetIdentifier
    }
}

struct FrameAppearance: Codable, Hashable {
    let timestamp: TimeInterval
    let bbox: CGRect
}

struct Sentence: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let rangeInImage: CGRect? // For static images
    var tokens: [Token]
    var pinyin: [String]
    var english: String?
    var plecoURL: URL
    var audioAsset: AudioAsset?
    var status: SentenceStatus
    var timestamp: TimeInterval? // Deprecated - kept for backwards compatibility
    var frameAppearances: [FrameAppearance]? // For videos: all frames where this text appears
    
    init(id: UUID = UUID(), text: String, rangeInImage: CGRect? = nil, tokens: [Token] = [], pinyin: [String] = [], english: String? = nil, plecoURL: URL? = nil, audioAsset: AudioAsset? = nil, status: SentenceStatus = .pending, timestamp: TimeInterval? = nil, frameAppearances: [FrameAppearance]? = nil) {
        self.id = id
        self.text = text
        self.rangeInImage = rangeInImage
        self.tokens = tokens
        self.pinyin = pinyin
        self.english = english
        self.plecoURL = plecoURL ?? URL(string: "plecoapi://x-callback-url/s?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
        self.audioAsset = audioAsset
        self.status = status
        self.timestamp = timestamp
        self.frameAppearances = frameAppearances
    }
}

struct Token: Codable, Hashable {
    let text: String
    let bbox: CGRect?
    
    init(text: String, bbox: CGRect? = nil) {
        self.text = text
        self.bbox = bbox
    }
}

struct AudioAsset: Codable, Hashable {
    let sha: String
    let fileURL: URL
    let duration: TimeInterval
    
    init(sha: String, fileURL: URL, duration: TimeInterval) {
        self.sha = sha
        self.fileURL = fileURL
        self.duration = duration
    }
}

struct OCRResult {
    let text: String
    let bbox: CGRect
    let confidence: Float
}

struct OCRLine {
    let text: String
    let bbox: CGRect
    let words: [OCRResult]
}