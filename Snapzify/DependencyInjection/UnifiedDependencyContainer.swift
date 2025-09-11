import Foundation
import SwiftUI

// MARK: - Unified Dependency Container
/// Single source of truth for all dependency injection in the application
@MainActor
final class UnifiedDependencyContainer: ObservableObject {
    static let shared = UnifiedDependencyContainer()
    
    // Registry of dependencies
    private var services: [String: Any] = [:]
    private var factories: [String: () -> Any] = [:]
    private var singletons: [String: Any] = [:]
    
    // App State (preserved from ServiceContainer)
    let appState = AppState()
    
    private init() {
        registerAllServices()
    }
    
    // MARK: - Registration
    
    /// Register a service instance
    func register<T>(_ service: T, for type: T.Type, scope: Scope = .singleton) {
        let key = String(describing: type)
        
        switch scope {
        case .singleton:
            singletons[key] = service
        case .transient:
            services[key] = service
        case .factory(let factory):
            factories[key] = factory
        }
    }
    
    /// Register a factory for lazy initialization
    func registerFactory<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = factory
    }
    
    /// Register with protocol conformance
    func register<T, P>(_ service: T, as protocol: P.Type) where T: P {
        let key = String(describing: P.self)
        singletons[key] = service
    }
    
    // MARK: - Resolution
    
    /// Resolve a registered dependency
    func resolve<T>(_ type: T.Type) -> T {
        let key = String(describing: type)
        
        // Check singletons first
        if let service = singletons[key] as? T {
            return service
        }
        
        // Check factories
        if let factory = factories[key] {
            if let service = factory() as? T {
                // Cache if singleton
                if singletons[key] == nil {
                    singletons[key] = service
                }
                return service
            }
        }
        
        // Check transient services
        if let service = services[key] as? T {
            return service
        }
        
        fatalError("⚠️ Dependency \(type) not registered!")
    }
    
    /// Safely resolve a dependency (returns optional)
    func safeResolve<T>(_ type: T.Type) -> T? {
        let key = String(describing: type)
        
        if let service = singletons[key] as? T {
            return service
        }
        
        if let factory = factories[key], let service = factory() as? T {
            return service
        }
        
        return services[key] as? T
    }
    
    // MARK: - Scope Management
    
    enum Scope {
        case singleton
        case transient
        case factory(() -> Any)
    }
    
    /// Clear all transient services
    func clearTransients() {
        services.removeAll()
    }
    
    /// Reset entire container
    func reset() {
        services.removeAll()
        factories.removeAll()
        singletons.removeAll()
        registerAllServices()
    }
    
    // MARK: - Service Registration
    
    private func registerAllServices() {
        // Core Services
        let configService = ConfigServiceImpl()
        register(configService, as: ConfigService.self)
        
        let documentStore = DocumentStoreImpl()
        register(documentStore, as: DocumentStore.self)
        
        // Processing Services
        let ocrService = OCRServiceImpl()
        register(ocrService, as: OCRService.self)
        
        let scriptConversionService = ScriptConversionServiceImpl()
        register(scriptConversionService, as: ScriptConversionService.self)
        
        let chineseProcessingService = ChineseProcessingService(configService: configService)
        register(chineseProcessingService, for: ChineseProcessingService.self)
        
        let streamingChineseProcessingService = StreamingChineseProcessingService(configService: configService)
        register(streamingChineseProcessingService, for: StreamingChineseProcessingService.self)
        
        // Translation & Audio Services
        let translationService = TranslationServiceOpenAI(configService: configService)
        register(translationService, as: TranslationService.self)
        
        let ttsService = TTSServiceOpenAI(configService: configService)
        register(ttsService, as: TTSService.self)
        
        let chatGPTService = ChatGPTServiceImpl(configService: configService)
        register(chatGPTService, for: ChatGPTServiceImpl.self)
        
        let englishToChineseTranslationService = EnglishToChineseTranslationServiceImpl(configService: configService)
        register(englishToChineseTranslationService, for: EnglishToChineseTranslationServiceImpl.self)
        
        // Document Management
        let documentService = DocumentServiceImpl(store: documentStore)
        register(documentService, as: DocumentService.self)
        
        // Media Services (from refactored code)
        register(MediaStorageService.shared, for: MediaStorageService.self)
        register(DocumentCacheManager.shared, for: DocumentCacheManager.self)
        register(KeychainService.shared, for: KeychainService.self)
        register(ErrorRecoveryManager.shared, for: ErrorRecoveryManager.self)
        
        // Register factories for services that need lazy initialization
        registerFactory(PhotoLibraryService.self) {
            PhotoLibraryService()
        }
        
        registerFactory(MediaProcessingService.self) { [weak self] in
            guard let self = self else {
                fatalError("UnifiedDependencyContainer deallocated")
            }
            
            return MediaProcessingService(
                store: self.resolve(DocumentStore.self),
                ocrService: self.resolve(OCRService.self),
                scriptConversionService: self.resolve(ScriptConversionService.self),
                chineseProcessingService: self.resolve(ChineseProcessingService.self),
                streamingChineseProcessingService: self.resolve(StreamingChineseProcessingService.self)
            )
        }
    }
    
    // MARK: - Convenience Accessors (for backward compatibility during migration)
    
    var configService: ConfigService {
        resolve(ConfigService.self)
    }
    
    var documentStore: DocumentStore {
        resolve(DocumentStore.self)
    }
    
    var ocrService: OCRService {
        resolve(OCRService.self)
    }
    
    var scriptConversionService: ScriptConversionService {
        resolve(ScriptConversionService.self)
    }
    
    var chineseProcessingService: ChineseProcessingService {
        resolve(ChineseProcessingService.self)
    }
    
    var streamingChineseProcessingService: StreamingChineseProcessingService {
        resolve(StreamingChineseProcessingService.self)
    }
    
    var translationService: TranslationService {
        resolve(TranslationService.self)
    }
    
    var ttsService: TTSService {
        resolve(TTSService.self)
    }
    
    var chatGPTService: ChatGPTServiceImpl {
        resolve(ChatGPTServiceImpl.self)
    }
    
    var englishToChineseTranslationService: EnglishToChineseTranslationServiceImpl {
        resolve(EnglishToChineseTranslationServiceImpl.self)
    }
    
    var documentService: DocumentService {
        resolve(DocumentService.self)
    }
    
    // MARK: - Factory Methods (preserved from ServiceContainer for compatibility)
    
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
    
    func makeDocumentViewModel(document: Document) -> DocumentViewModel {
        return DocumentViewModel(
            document: document,
            translationService: translationService,
            ttsService: ttsService,
            store: documentStore
        )
    }
    
    func makeSettingsViewModel() -> SettingsViewModel {
        return SettingsViewModel(
            configService: configService,
            translationService: translationService,
            ttsService: ttsService
        )
    }
}

// MARK: - Property Wrapper for Dependency Injection
@propertyWrapper
struct Inject<T> {
    private var resolvedValue: T?
    
    var wrappedValue: T {
        get {
            if let resolvedValue = resolvedValue {
                return resolvedValue
            }
            return UnifiedDependencyContainer.shared.resolve(T.self)
        }
        mutating set {
            resolvedValue = newValue
        }
    }
    
    init() {
        self.resolvedValue = nil
    }
    
    init(default value: T) {
        self.resolvedValue = value
    }
}

// MARK: - Environment Injection for SwiftUI
struct UnifiedDependencyEnvironmentKey: EnvironmentKey {
    static let defaultValue = UnifiedDependencyContainer.shared
}

extension EnvironmentValues {
    var dependencies: UnifiedDependencyContainer {
        get { self[UnifiedDependencyEnvironmentKey.self] }
        set { self[UnifiedDependencyEnvironmentKey.self] = newValue }
    }
}

// MARK: - View Modifier for Dependency Injection
struct InjectDependencies: ViewModifier {
    let container: UnifiedDependencyContainer
    
    func body(content: Content) -> some View {
        content
            .environmentObject(container)
            .environment(\.dependencies, container)
    }
}

extension View {
    func injectDependencies(_ container: UnifiedDependencyContainer = .shared) -> some View {
        modifier(InjectDependencies(container: container))
    }
}