import Foundation
import SwiftUI

class ServiceContainer {
    static let shared = ServiceContainer()
    
    // Core Services
    let configService: ConfigService
    let documentStore: DocumentStore
    
    // Processing Services
    let ocrService: OCRService
    let scriptConversionService: ScriptConversionService
    let chineseProcessingService: ChineseProcessingService
    let streamingChineseProcessingService: StreamingChineseProcessingService
    
    // Translation & Audio Services
    let translationService: TranslationService
    let ttsService: TTSService
    let chatGPTService: ChatGPTService
    let englishToChineseTranslationService: EnglishToChineseTranslationService
    
    // Document Management
    let documentService: DocumentService
    
    // App State
    let appState = AppState()
    
    private init() {
        // Initialize core services
        self.configService = ConfigServiceImpl()
        self.documentStore = DocumentStoreImpl()
        
        // Initialize processing services
        self.ocrService = OCRServiceImpl()
        self.scriptConversionService = ScriptConversionServiceImpl()
        self.chineseProcessingService = ChineseProcessingService(configService: configService)
        self.streamingChineseProcessingService = StreamingChineseProcessingService(configService: configService)
        
        // Initialize translation & audio services
        self.translationService = TranslationServiceOpenAI(configService: configService)
        self.ttsService = TTSServiceOpenAI(configService: configService)
        self.chatGPTService = ChatGPTServiceImpl(configService: configService)
        self.englishToChineseTranslationService = EnglishToChineseTranslationServiceImpl(configService: configService)
        
        // Initialize document service
        self.documentService = DocumentServiceImpl(store: documentStore)
    }
    
    // Factory method for creating ViewModels with injected dependencies
    @MainActor
    func makeHomeViewModel(
        onOpenSettings: @escaping () -> Void,
        onOpenDocument: @escaping (Document) -> Void
    ) -> HomeViewModel {
        return HomeViewModel(
            store: documentStore,
            ocrService: ocrService,
            scriptConversionService: scriptConversionService,
            onOpenSettings: onOpenSettings,
            onOpenDocument: onOpenDocument
        )
    }
    
    @MainActor
    func makeDocumentViewModel(document: Document) -> DocumentViewModel {
        return DocumentViewModel(
            document: document,
            translationService: translationService,
            ttsService: ttsService,
            store: documentStore
        )
    }
    
    @MainActor
    func makeSettingsViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            configService: configService,
            translationService: translationService,
            ttsService: ttsService
        )
    }
    
    // Generic resolve method for dependency injection
    func resolve<T>(_ type: T.Type) -> T? {
        switch type {
        case is ConfigService.Type:
            return configService as? T
        case is DocumentStore.Type:
            return documentStore as? T
        case is OCRService.Type:
            return ocrService as? T
        case is ScriptConversionService.Type:
            return scriptConversionService as? T
        case is ChineseProcessingService.Type:
            return chineseProcessingService as? T
        case is StreamingChineseProcessingService.Type:
            return streamingChineseProcessingService as? T
        case is TranslationService.Type:
            return translationService as? T
        case is TTSService.Type:
            return ttsService as? T
        case is ChatGPTService.Type:
            return chatGPTService as? T
        case is EnglishToChineseTranslationService.Type:
            return englishToChineseTranslationService as? T
        case is DocumentService.Type:
            return documentService as? T
        case is AppState.Type:
            return appState as? T
        default:
            return nil
        }
    }
}