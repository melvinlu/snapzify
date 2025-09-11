import Foundation
import SwiftUI

// MARK: - Temporary Migration Bridge
// This file provides a bridge between the old ServiceContainer and new UnifiedDependencyContainer
// It allows gradual migration without breaking existing code

// Create a global accessor that maps to ServiceContainer for now
// This avoids the need to update all files immediately
let UnifiedDependencyContainer = ServiceContainer.self

// Extension to make ServiceContainer compatible with the new API
extension ServiceContainer {
    // Add methods that match UnifiedDependencyContainer API
    func get<T>(_ type: T.Type) -> T {
        guard let service = resolve(type) else {
            fatalError("Service \(type) not registered")
        }
        return service
    }
    
    func safeResolve<T>(_ type: T.Type) -> T? {
        return resolve(type)
    }
}