import XCTest
import Foundation
@testable import Snapzify

// MARK: - Test Base Class
class SnapzifyTestCase: XCTestCase {
    var container: MockDependencyContainer!
    
    override func setUp() {
        super.setUp()
        container = MockDependencyContainer()
        setupMocks()
    }
    
    override func tearDown() {
        container.reset()
        container = nil
        super.tearDown()
    }
    
    /// Override to setup specific mocks for test
    func setupMocks() {
        // Default mock setup
    }
    
    // MARK: - Helper Methods
    
    func waitForAsync(
        timeout: TimeInterval = 5,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: @escaping () async throws -> Void
    ) {
        let expectation = XCTestExpectation(description: "Async operation")
        
        Task {
            do {
                try await block()
                expectation.fulfill()
            } catch {
                XCTFail("Async operation failed: \(error)", file: file, line: line)
            }
        }
        
        wait(for: [expectation], timeout: timeout)
    }
    
    func measureAsync(
        _ block: @escaping () async throws -> Void
    ) {
        measure {
            let expectation = XCTestExpectation()
            Task {
                try await block()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10)
        }
    }
}

// MARK: - Mock Services

// Mock Document Store
class MockDocumentStore: DocumentStore {
    var documents: [Document] = []
    var shouldThrowError = false
    var saveCallCount = 0
    var fetchCallCount = 0
    
    func save(_ document: Document) async throws {
        saveCallCount += 1
        if shouldThrowError {
            throw TestError.mock
        }
        documents.append(document)
    }
    
    func fetch(id: UUID) async throws -> Document? {
        fetchCallCount += 1
        if shouldThrowError {
            throw TestError.mock
        }
        return documents.first { $0.id == id }
    }
    
    func fetchAll() async throws -> [Document] {
        if shouldThrowError {
            throw TestError.mock
        }
        return documents
    }
    
    func delete(id: UUID) async throws {
        if shouldThrowError {
            throw TestError.mock
        }
        documents.removeAll { $0.id == id }
    }
    
    func update(_ document: Document) async throws {
        if shouldThrowError {
            throw TestError.mock
        }
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        }
    }
    
    func fetchRecentMetadata(limit: Int) async throws -> [DocumentMetadata] {
        Array(documents.prefix(limit).map { DocumentMetadata(from: $0) })
    }
    
    func fetchSavedMetadata() async throws -> [DocumentMetadata] {
        documents.filter { $0.isSaved }.map { DocumentMetadata(from: $0) }
    }
}

// Mock OCR Service
class MockOCRService: OCRService {
    var mockResult: [OCRLine] = []
    var shouldThrowError = false
    var recognizeCallCount = 0
    
    func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        recognizeCallCount += 1
        if shouldThrowError {
            throw TestError.mock
        }
        return mockResult
    }
}

// Mock Translation Service
class MockTranslationService: TranslationService {
    var mockTranslations: [String: String] = [:]
    var shouldThrowError = false
    var translateCallCount = 0
    
    func translate(_ text: String) async throws -> String {
        translateCallCount += 1
        if shouldThrowError {
            throw TestError.mock
        }
        return mockTranslations[text] ?? "Mock translation"
    }
    
    func translateBatch(_ texts: [String]) async throws -> [String] {
        if shouldThrowError {
            throw TestError.mock
        }
        return texts.map { mockTranslations[$0] ?? "Mock translation" }
    }
    
    func isConfigured() -> Bool {
        !shouldThrowError
    }
}

// Mock Photo Library Service
class MockPhotoLibraryService: PhotoLibraryService {
    var mockAssets: [PHAsset] = []
    var shouldThrowError = false
    
    override func fetchLatestAsset(newerThan date: Date?) async -> LatestAssetInfo? {
        if shouldThrowError { return nil }
        return nil // Mock implementation
    }
}

// MARK: - Test Errors
enum TestError: Error {
    case mock
    case timeout
    case invalidData
}

// MARK: - Test Data Factory
struct TestDataFactory {
    static func makeDocument(
        id: UUID = UUID(),
        sentences: Int = 5,
        isSaved: Bool = false
    ) -> Document {
        let testSentences = (0..<sentences).map { index in
            Sentence(
                text: "Test sentence \(index)",
                rangeInImage: CGRect(x: 0, y: CGFloat(index * 50), width: 100, height: 40),
                pinyin: ["test", "pinyin"],
                english: "Test translation \(index)"
            )
        }
        
        return Document(
            id: id,
            source: .imported,
            sentences: testSentences,
            isSaved: isSaved
        )
    }
    
    static func makeImage(
        width: Int = 100,
        height: Int = 100,
        color: UIColor = .white
    ) -> UIImage {
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        color.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    static func makeOCRLine(text: String = "测试文字") -> OCRLine {
        OCRLine(
            text: text,
            bbox: CGRect(x: 0, y: 0, width: 100, height: 20),
            words: [OCRResult(text: text, bbox: CGRect(x: 0, y: 0, width: 100, height: 20), confidence: 0.95)]
        )
    }
}

// MARK: - Performance Testing
class PerformanceTestCase: SnapzifyTestCase {
    func measureMemory(
        _ block: () throws -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let startMemory = getMemoryUsage()
        
        do {
            try block()
        } catch {
            XCTFail("Operation failed: \(error)", file: file, line: line)
        }
        
        let endMemory = getMemoryUsage()
        let memoryIncrease = endMemory - startMemory
        
        XCTAssertLessThan(
            memoryIncrease,
            50_000_000, // 50MB threshold
            "Memory usage increased by \(memoryIncrease / 1_000_000)MB",
            file: file,
            line: line
        )
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

// MARK: - Assertion Helpers
extension XCTestCase {
    func XCTAssertThrowsAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error but none was thrown. \(message())", file: file, line: line)
        } catch {
            // Success - error was thrown
        }
    }
    
    func XCTAssertNoThrowAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> T? {
        do {
            return try await expression()
        } catch {
            XCTFail("Unexpected error: \(error). \(message())", file: file, line: line)
            return nil
        }
    }
    
    func XCTAssertEqualAsync<T: Equatable>(
        _ expression1: @autoclosure () async -> T,
        _ expression2: @autoclosure () async -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let value1 = await expression1()
        let value2 = await expression2()
        XCTAssertEqual(value1, value2, message(), file: file, line: line)
    }
}

// MARK: - UI Testing Helpers
#if canImport(XCTest)
extension XCUIElement {
    func waitForExistence(timeout: TimeInterval = 5) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }
    
    func clearAndEnterText(_ text: String) {
        guard self.exists else { return }
        
        self.tap()
        
        // Clear existing text
        if let value = self.value as? String, !value.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
            self.typeText(deleteString)
        }
        
        self.typeText(text)
    }
}

extension XCUIApplication {
    func waitForLaunch(timeout: TimeInterval = 10) {
        _ = self.wait(for: .runningForeground, timeout: timeout)
    }
}
#endif