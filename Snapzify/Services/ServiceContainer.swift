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
}