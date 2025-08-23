// The Swift Programming Language
// https://docs.swift.org/swift-book

// SnapzifyCore - Shared code between main app and ShareExtension

// Export all public types for external use
public typealias Document = Document
public typealias Sentence = Sentence
public typealias OCRLine = OCRLine
public typealias ChineseScript = ChineseScript

// Export all services for external use
public typealias OCRService = OCRService
public typealias ConfigService = ConfigService
public typealias ScriptConversionService = ScriptConversionService
public typealias SentenceSegmentationService = SentenceSegmentationService
public typealias PinyinService = PinyinService

// Export all service implementations
public typealias OCRServiceImpl = OCRServiceImpl
public typealias ConfigServiceImpl = ConfigServiceImpl
public typealias ScriptConversionServiceImpl = ScriptConversionServiceImpl
public typealias SentenceSegmentationServiceImpl = SentenceSegmentationServiceImpl
public typealias PinyinServiceImpl = PinyinServiceImpl

// Export theme
public typealias T = T