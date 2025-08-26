import Foundation
import SwiftUI

// MARK: - Dependency Container
/// Main dependency injection container for the application
@MainActor
final class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()
    
    // Registry of dependencies
    private var services: [String: Any] = [:]
    private var factories: [String: () -> Any] = [:]
    private var singletons: [String: Any] = [:]
    
    private init() {
        registerDefaults()
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
        registerDefaults()
    }
    
    // MARK: - Default Registrations
    
    private func registerDefaults() {
        // Register all default services
        registerFactory(DocumentStore.self) {
            DocumentStoreImpl()
        }
        
        registerFactory(OCRService.self) {
            OCRServiceImpl()
        }
        
        registerFactory(TranslationService.self) {
            TranslationServiceOpenAI()
        }
        
        registerFactory(TTSService.self) {
            TTSServiceImpl()
        }
        
        registerFactory(ChineseProcessingService.self) {
            ServiceContainer.shared.chineseProcessingService
        }
        
        registerFactory(StreamingChineseProcessingService.self) {
            ServiceContainer.shared.streamingChineseProcessingService
        }
        
        registerFactory(ScriptConversionService.self) {
            ScriptConversionServiceOpenCC()
        }
        
        // Register new services
        register(MediaStorageService.shared, for: MediaStorageService.self)
        register(DocumentCacheManager.shared, for: DocumentCacheManager.self)
        register(KeychainService.shared, for: KeychainService.self)
        register(ErrorRecoveryManager.shared, for: ErrorRecoveryManager.self)
        
        // Register factories for new services
        registerFactory(PhotoLibraryService.self) {
            PhotoLibraryService()
        }
        
        registerFactory(MediaProcessingService.self) { [weak self] in
            guard let self = self else {
                fatalError("DependencyContainer deallocated")
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
}

// MARK: - Property Wrapper for Dependency Injection
@propertyWrapper
struct Injected<T> {
    private let keyPath: WritableKeyPath<DependencyContainer, T>?
    private var resolvedValue: T?
    
    var wrappedValue: T {
        get {
            if let resolvedValue = resolvedValue {
                return resolvedValue
            }
            return DependencyContainer.shared.resolve(T.self)
        }
        mutating set {
            resolvedValue = newValue
        }
    }
    
    init() {
        self.keyPath = nil
    }
}

// MARK: - Environment Injection for SwiftUI
struct DependencyEnvironmentKey: EnvironmentKey {
    static let defaultValue = DependencyContainer.shared
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyEnvironmentKey.self] }
        set { self[DependencyEnvironmentKey.self] = newValue }
    }
}

// MARK: - View Modifier for Dependency Injection
struct WithDependencies: ViewModifier {
    let container: DependencyContainer
    
    func body(content: Content) -> some View {
        content
            .environment(\.dependencies, container)
    }
}

extension View {
    func withDependencies(_ container: DependencyContainer = .shared) -> some View {
        modifier(WithDependencies(container: container))
    }
}

// MARK: - Injectable Protocol
protocol Injectable {
    associatedtype Dependencies
    init(dependencies: Dependencies)
}

// MARK: - Service Locator Pattern (Alternative)
final class ServiceLocator {
    static let shared = ServiceLocator()
    private let container = DependencyContainer.shared
    
    private init() {}
    
    func get<T>(_ type: T.Type) -> T {
        container.resolve(type)
    }
    
    func getOptional<T>(_ type: T.Type) -> T? {
        container.safeResolve(type)
    }
}

// MARK: - Mock Container for Testing
class MockDependencyContainer: DependencyContainer {
    override init() {
        super.init()
        registerMocks()
    }
    
    private func registerMocks() {
        // Register mock services for testing
        // This would be implemented in test targets
    }
}

// MARK: - Dependency Builder
/// Builder pattern for complex dependency setup
class DependencyBuilder {
    private var registrations: [(Any, Any.Type, DependencyContainer.Scope)] = []
    
    @discardableResult
    func add<T>(_ service: T, for type: T.Type, scope: DependencyContainer.Scope = .singleton) -> Self {
        registrations.append((service, type, scope))
        return self
    }
    
    @discardableResult
    func addFactory<T>(_ type: T.Type, factory: @escaping () -> T) -> Self {
        registrations.append((factory, type, .factory(factory)))
        return self
    }
    
    func build() -> DependencyContainer {
        let container = DependencyContainer.shared
        
        for (service, type, scope) in registrations {
            // This would need proper type handling
            // Simplified for illustration
            container.services[String(describing: type)] = service
        }
        
        return container
    }
}

// MARK: - Module Registration
protocol DependencyModule {
    func register(in container: DependencyContainer)
}

struct NetworkingModule: DependencyModule {
    func register(in container: DependencyContainer) {
        // Register networking-related services
    }
}

struct DataModule: DependencyModule {
    func register(in container: DependencyContainer) {
        // Register data-related services
    }
}

struct UIModule: DependencyModule {
    func register(in container: DependencyContainer) {
        // Register UI-related services
    }
}

// MARK: - Usage Examples
/*
// In a ViewModel:
class ExampleViewModel: ObservableObject {
    @Injected private var documentStore: DocumentStore
    @Injected private var ocrService: OCRService
    
    func processDocument() async {
        // Use injected services
    }
}

// In a View:
struct ExampleView: View {
    @Environment(\.dependencies) private var dependencies
    
    var body: some View {
        Text("Example")
            .onAppear {
                let store = dependencies.resolve(DocumentStore.self)
                // Use store
            }
    }
}

// In tests:
func testExample() {
    let mockContainer = MockDependencyContainer()
    mockContainer.register(MockDocumentStore(), for: DocumentStore.self)
    
    // Test with mocks
}
*/