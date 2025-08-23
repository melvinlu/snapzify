import XCTest
@testable import Snapzify

final class ServiceTests: XCTestCase {
    
    func testScriptConversionSimplifiedToTraditional() {
        let service = ScriptConversionServiceImpl()
        
        let testCases = [
            ("爱", "愛"),
            ("学习", "學習"),
            ("简体中文", "簡體中文"),
            ("这是测试", "這是測試")
        ]
        
        for (simplified, expectedTraditional) in testCases {
            let result = service.toTraditional(simplified)
            XCTAssertEqual(result, expectedTraditional, "Failed to convert '\(simplified)' to traditional")
        }
    }
    
    func testScriptConversionTraditionalToSimplified() {
        let service = ScriptConversionServiceImpl()
        
        let testCases = [
            ("愛", "爱"),
            ("學習", "学习"),
            ("繁體中文", "繁体中文"),
            ("這是測試", "这是测试")
        ]
        
        for (traditional, expectedSimplified) in testCases {
            let result = service.toSimplified(traditional)
            XCTAssertEqual(result, expectedSimplified, "Failed to convert '\(traditional)' to simplified")
        }
    }
    
    func testScriptConversionIdempotence() {
        let service = ScriptConversionServiceImpl()
        
        let text = "这是一个测试"
        let toTraditional = service.toTraditional(text)
        let backToSimplified = service.toSimplified(toTraditional)
        
        XCTAssertEqual(text, backToSimplified, "Conversion should be roughly idempotent")
    }
    
    func testSentenceSegmentation() {
        let service = SentenceSegmentationServiceImpl()
        
        let lines = [
            OCRLine(text: "你好，世界。", bbox: CGRect(x: 0, y: 0, width: 100, height: 20), words: []),
            OCRLine(text: "这是第二句！", bbox: CGRect(x: 0, y: 25, width: 100, height: 20), words: []),
            OCRLine(text: "第三句？第四句。", bbox: CGRect(x: 0, y: 50, width: 100, height: 20), words: [])
        ]
        
        let sentences = service.segmentIntoSentences(from: lines)
        
        XCTAssertEqual(sentences.count, 4, "Should detect 4 sentences")
        XCTAssertEqual(sentences[0].text, "你好，世界。")
        XCTAssertEqual(sentences[1].text, "这是第二句！")
        XCTAssertEqual(sentences[2].text, "第三句？")
        XCTAssertEqual(sentences[3].text, "第四句。")
    }
    
    func testSentenceSegmentationWithQuotes() {
        let service = SentenceSegmentationServiceImpl()
        
        let lines = [
            OCRLine(text: "他说："你好。"", bbox: CGRect(x: 0, y: 0, width: 100, height: 20), words: []),
            OCRLine(text: "然后离开了。", bbox: CGRect(x: 0, y: 25, width: 100, height: 20), words: [])
        ]
        
        let sentences = service.segmentIntoSentences(from: lines)
        
        XCTAssertEqual(sentences.count, 2, "Should detect 2 sentences")
        XCTAssertEqual(sentences[0].text, "他说："你好。"")
        XCTAssertEqual(sentences[1].text, "然后离开了。")
    }
    
    func testTokenization() {
        let service = SentenceSegmentationServiceImpl()
        
        let sentence = "我喜欢学习中文"
        let tokens = service.tokenize(sentence)
        
        XCTAssertGreaterThan(tokens.count, 0, "Should produce tokens")
        XCTAssertTrue(tokens.allSatisfy { !$0.text.isEmpty }, "All tokens should have text")
    }
    
    func testPinyinMapping() {
        let service = PinyinServiceImpl()
        
        let testCases = [
            ("你", ["nǐ"]),
            ("好", ["hǎo", "hào"]),
            ("中", ["zhōng", "zhòng"])
        ]
        
        for (character, expectedPinyin) in testCases {
            let result = service.getPinyin(for: character, script: .simplified)
            XCTAssertEqual(result.count, 1, "Should return one pinyin per character")
            XCTAssertTrue(expectedPinyin.contains(result[0]), "Pinyin for '\(character)' should be one of \(expectedPinyin)")
        }
    }
    
    func testPlecoURLGeneration() {
        let service = PlecoLinkServiceImpl()
        
        let sentence = "你好世界"
        let url = service.buildURL(for: sentence)
        
        XCTAssertTrue(url.absoluteString.hasPrefix("plecoapi://"))
        XCTAssertTrue(url.absoluteString.contains("q="))
        XCTAssertTrue(url.absoluteString.contains("%E4%BD%A0%E5%A5%BD")) // URL encoded "你好"
    }
    
    func testConfigServiceDefaults() {
        let service = ConfigServiceImpl()
        
        XCTAssertEqual(service.translationModel, "gpt-4o-mini")
        XCTAssertEqual(service.ttsModel, "tts-1")
        XCTAssertEqual(service.requestsPerBatch, 12)
        XCTAssertTrue(service.cloudTranslationEnabledDefault)
        XCTAssertTrue(service.cloudAudioEnabledDefault)
    }
    
    func testTranslationBatching() {
        // Mock test for translation batching logic
        let sentences = Array(repeating: "测试", count: 25)
        let batchSize = 12
        
        let chunks = sentences.chunked(into: batchSize)
        
        XCTAssertEqual(chunks.count, 3, "Should create 3 batches for 25 items with batch size 12")
        XCTAssertEqual(chunks[0].count, 12)
        XCTAssertEqual(chunks[1].count, 12)
        XCTAssertEqual(chunks[2].count, 1)
    }
    
    func testAudioCacheKey() {
        let text = "你好"
        let voice = "alloy"
        let script = ChineseScript.simplified
        
        let key = "\(text):\(voice):\(script.rawValue)".sha256()
        
        XCTAssertEqual(key.count, 64, "SHA256 should produce 64 character hex string")
        let hexCharset = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(key.allSatisfy { char in
            hexCharset.contains(char.unicodeScalars.first!)
        }, "Should only contain hex characters")
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}