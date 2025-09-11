import Foundation

// MARK: - Migration Helper
/// Temporary typealias to ease migration from ServiceContainer to UnifiedDependencyContainer
/// This allows us to update files incrementally without breaking the entire app
typealias DIContainer = UnifiedDependencyContainer

// MARK: - Global Accessor
/// Global accessor for dependency injection
/// Use @Inject property wrapper when possible
var DI: UnifiedDependencyContainer {
    UnifiedDependencyContainer.shared
}

// MARK: - Extension for cleaner syntax
extension UnifiedDependencyContainer {
    /// Convenience method for getting services with cleaner syntax
    func get<T>(_ type: T.Type) -> T {
        resolve(type)
    }
    
    /// Convenience method for safe resolution
    func getOptional<T>(_ type: T.Type) -> T? {
        safeResolve(type)
    }
}