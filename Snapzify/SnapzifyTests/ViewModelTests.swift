import XCTest
import SwiftUI
@testable import Snapzify

@MainActor
final class ViewModelTests: XCTestCase {
    
    func testHomeViewModelDocumentLoading() async {
        let mockStore = MockDocumentStore()
        let vm = HomeViewModel(
            store: mockStore,
            ocrService: MockOCRService(),
            scriptConversionService: ScriptConversionServiceImpl(),
            segmentationService: SentenceSegmentationServiceImpl(),
            pinyinService: PinyinServiceImpl()
        )
        
        mockStore.documents = [
            Document(source: .photos, script: .simplified),
            Document(source: .shareExtension, script: .traditional)
        ]
        
        await vm.loadDocuments()
        
        XCTAssertEqual(vm.documents.count, 2)
        XCTAssertEqual(vm.documents[0].source, .photos)
        XCTAssertEqual(vm.documents[1].source, .shareExtension)
    }
    
    func testSentenceViewModelExpansion() async {
        let sentence = Sentence(
            text: "你好世界",
            tokens: [Token(text: "你好"), Token(text: "世界")],
            pinyin: ["nǐ", "hǎo", "shì", "jiè"]
        )
        
        let vm = SentenceViewModel(
            sentence: sentence,
            script: .simplified,
            translationService: MockTranslationService(),
            ttsService: MockTTSService(),
            autoTranslate: true,
            autoGenerateAudio: true
        ) { _ in }
        
        XCTAssertFalse(vm.isExpanded)
        
        vm.toggleExpanded()
        
        XCTAssertTrue(vm.isExpanded)
    }
    
    func testSettingsViewModelAPIKeyValidation() async {
        let vm = SettingsViewModel(
            configService: MockConfigService(),
            translationService: MockTranslationService(),
            ttsService: MockTTSService()
        )
        
        XCTAssertFalse(vm.isAPIKeyValid)
        
        vm.apiKey = "sk-test-key-123"
        await vm.testAPIKey()
        
        XCTAssertTrue(vm.isAPIKeyValid)
    }
    
    func testDocumentViewModelTranslationBatch() async {
        let sentences = (1...5).map { i in
            Sentence(text: "句子\(i)", status: .ocrOnly)
        }
        
        let document = Document(
            source: .photos,
            script: .simplified,
            sentences: sentences
        )
        
        let vm = DocumentViewModel(
            document: document,
            translationService: MockTranslationService(),
            ttsService: MockTTSService(),
            store: MockDocumentStore()
        )
        
        await vm.translateAllPending()
        
        XCTAssertEqual(vm.document.sentences.filter { $0.english != nil }.count, 5)
    }
}

// MARK: - Mock Services

class MockDocumentStore: DocumentStore {
    var documents: [Document] = []
    var saveCallCount = 0
    
    func save(_ document: Document) async throws {
        saveCallCount += 1
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.append(document)
        }
    }
    
    func fetchAll() async throws -> [Document] {
        return documents.sorted { $0.createdAt > $1.createdAt }
    }
    
    func fetch(id: UUID) async throws -> Document? {
        return documents.first { $0.id == id }
    }
    
    func delete(id: UUID) async throws {
        documents.removeAll { $0.id == id }
    }
    
    func fetchLatest() async throws -> Document? {
        return documents.sorted { $0.createdAt > $1.createdAt }.first
    }
}

class MockOCRService: OCRService {
    func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        return [
            OCRLine(text: "测试文本", bbox: CGRect(x: 0, y: 0, width: 100, height: 20), words: [])
        ]
    }
}

class MockTranslationService: TranslationService {
    func translate(_ sentences: [String]) async throws -> [String?] {
        return sentences.map { "Translation of: \($0)" }
    }
    
    func isConfigured() -> Bool {
        return true
    }
}

class MockTTSService: TTSService {
    func generateAudio(for text: String, script: ChineseScript) async throws -> AudioAsset {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        return AudioAsset(sha: "test-sha", fileURL: url, duration: 1.5)
    }
    
    func isConfigured() -> Bool {
        return true
    }
}

class MockConfigService: ConfigService {
    var openAIKey: String? = "test-key"
    var translationModel = "gpt-4o-mini"
    var ttsModel = "tts-1"
    var defaultVoiceSimplified = "alloy"
    var defaultVoiceTraditional = "nova"
    var requestsPerBatch = 12
    var cloudTranslationEnabledDefault = true
    var cloudAudioEnabledDefault = true
    
    func updateAPIKey(_ key: String?) {
        openAIKey = key
    }
}