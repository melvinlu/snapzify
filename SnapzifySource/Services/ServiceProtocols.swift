import Foundation
import UIKit
import Vision
import AVFoundation

protocol OCRService {
    func recognizeText(in image: UIImage) async throws -> [OCRLine]
}

protocol ScriptConversionService {
    func toSimplified(_ text: String) -> String
    func toTraditional(_ text: String) -> String
}

protocol SentenceSegmentationService {
    func segmentIntoSentences(from lines: [OCRLine]) async -> [(text: String, bbox: CGRect)]
    func tokenize(_ sentence: String) async -> [Token]
}

protocol PinyinService {
    func getPinyin(for text: String, script: ChineseScript) async -> [String]
    func getPinyinForTokens(_ tokens: [Token], script: ChineseScript) async -> [String]
}

protocol TranslationService {
    func translate(_ sentences: [String]) async throws -> [String?]
    func isConfigured() -> Bool
}

protocol TTSService {
    func generateAudio(for text: String, script: ChineseScript) async throws -> AudioAsset
    func isConfigured() -> Bool
}

protocol PlecoLinkService {
    func buildURL(for sentence: String) -> URL
    func canOpenPleco() -> Bool
}

protocol ConfigService {
    var openAIKey: String? { get }
    var translationModel: String { get }
    var ttsModel: String { get }
    var defaultVoiceSimplified: String { get }
    var defaultVoiceTraditional: String { get }
    var requestsPerBatch: Int { get }
    var cloudTranslationEnabledDefault: Bool { get }
    var cloudAudioEnabledDefault: Bool { get }
    
    func updateAPIKey(_ key: String?)
}

protocol DocumentStore {
    func save(_ document: Document) async throws
    func fetchAll() async throws -> [Document]
    func fetch(id: UUID) async throws -> Document?
    func delete(id: UUID) async throws
    func fetchLatest() async throws -> Document?
    func deleteAll() async throws
    func update(_ document: Document) async throws
    func fetchPinned() async throws -> [Document]
    func fetchSaved() async throws -> [Document]
}