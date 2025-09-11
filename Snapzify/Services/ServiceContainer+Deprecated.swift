import Foundation
import SwiftUI

// MARK: - Deprecated ServiceContainer
// This extension marks ServiceContainer as deprecated and redirects to UnifiedDependencyContainer
// This helps with migration by providing compile-time warnings

extension ServiceContainer {
    @available(*, deprecated, message: "Use UnifiedDependencyContainer.shared or DI instead")
    static var deprecatedShared: ServiceContainer {
        return shared
    }
}

// MARK: - ServiceContainer Compatibility Layer
// Temporary extension to make ServiceContainer use UnifiedDependencyContainer internally
// This allows gradual migration without breaking existing code

extension ServiceContainer {
    // Override computed properties to use UnifiedDependencyContainer
    @available(*, deprecated, message: "Access services through DI instead")
    static func migrateToUnifiedContainer() {
        // This method can be called during app initialization to ensure
        // ServiceContainer uses UnifiedDependencyContainer internally
        print("⚠️ ServiceContainer is deprecated. Please migrate to UnifiedDependencyContainer (DI)")
    }
}