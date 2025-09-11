import Foundation
import SwiftUI
import os.log

// MARK: - Error Recovery Manager
/// Centralized error handling and recovery system
@MainActor
final class ErrorRecoveryManager: ObservableObject {
    static let shared = ErrorRecoveryManager()
    
    private let logger = Logger(subsystem: "com.snapzify.app", category: "ErrorRecovery")
    
    // Published properties for UI binding
    @Published var currentError: (any SnapzifyError)?
    @Published var isShowingError = false
    @Published var errorHistory: [ErrorEntry] = []
    
    // Error tracking
    private var errorCounts: [String: Int] = [:]
    private let maxErrorHistorySize = 50
    private let errorThrottleInterval: TimeInterval = 5.0
    private var lastErrorTimes: [String: Date] = [:]
    
    // Recovery actions
    private var recoveryHandlers: [String: () async throws -> Void] = [:]
    
    struct ErrorEntry: Identifiable {
        let id = UUID()
        let error: any SnapzifyError
        let timestamp: Date
        let context: String?
        let recovered: Bool
    }
    
    private init() {
        setupDefaultRecoveryHandlers()
    }
    
    // MARK: - Error Handling
    
    /// Handle an error with optional context
    func handle(_ error: Error, context: String? = nil) {
        logger.error("Error occurred: \(error.localizedDescription), context: \(context ?? "none")")
        
        // Convert to SnapzifyError if needed
        let snapzifyError: any SnapzifyError
        if let sError = error as? any SnapzifyError {
            snapzifyError = sError
        } else {
            snapzifyError = GenericError(underlyingError: error)
        }
        
        // Check for throttling
        let errorKey = String(describing: type(of: snapzifyError))
        if shouldThrottle(errorKey: errorKey) {
            logger.debug("Throttling error: \(errorKey)")
            return
        }
        
        // Track error
        trackError(snapzifyError, context: context)
        
        // Show error if recoverable or first occurrence
        if snapzifyError.isRecoverable || errorCounts[errorKey] == 1 {
            Task { @MainActor in
                self.currentError = snapzifyError
                self.isShowingError = true
            }
        }
        
        // Auto-recover if possible
        if snapzifyError.suggestedAction == .retry {
            attemptAutoRecovery(for: snapzifyError)
        }
    }
    
    /// Handle multiple errors (batch processing)
    func handleBatch(_ errors: [Error], context: String? = nil) {
        guard !errors.isEmpty else { return }
        
        logger.error("Batch errors occurred: \(errors.count) errors")
        
        // Group similar errors
        let groupedErrors = Dictionary(grouping: errors) { error in
            String(describing: type(of: error))
        }
        
        // Show most critical error
        if let criticalError = findMostCriticalError(in: errors) {
            handle(criticalError, context: context)
        }
        
        // Log summary
        for (errorType, errors) in groupedErrors {
            logger.info("\(errorType): \(errors.count) occurrences")
        }
    }
    
    // MARK: - Recovery Actions
    
    /// Attempt recovery for an error
    func attemptRecovery(for error: any SnapzifyError) async -> Bool {
        logger.info("Attempting recovery for: \(String(describing: type(of: error)))")
        
        guard let action = error.suggestedAction else {
            logger.debug("No recovery action available")
            return false
        }
        
        do {
            switch action {
            case .retry:
                if let handler = recoveryHandlers["retry"] {
                    try await handler()
                    recordRecovery(for: error, success: true)
                    return true
                }
                
            case .checkNetwork:
                if await checkNetworkConnectivity() {
                    recordRecovery(for: error, success: true)
                    return true
                }
                
            case .checkStorage:
                if await checkStorageSpace() {
                    recordRecovery(for: error, success: true)
                    return true
                }
                
            case .checkPermissions:
                if await checkPermissions() {
                    recordRecovery(for: error, success: true)
                    return true
                }
                
            case .configureSettings:
                await openSettings()
                return false // User must complete action
                
            case .contactSupport:
                await showSupportInfo()
                return false
            }
        } catch {
            logger.error("Recovery failed: \(error.localizedDescription)")
            recordRecovery(for: error, success: false)
        }
        
        return false
    }
    
    /// Register a custom recovery handler
    func registerRecoveryHandler(for key: String, handler: @escaping () async throws -> Void) {
        recoveryHandlers[key] = handler
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultRecoveryHandlers() {
        // Setup default retry handler
        recoveryHandlers["retry"] = { [weak self] in
            // Default retry logic - can be overridden
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            self?.logger.info("Retry attempted")
        }
    }
    
    private func trackError(_ error: any SnapzifyError, context: String?) {
        let errorKey = String(describing: type(of: error))
        
        // Update count
        errorCounts[errorKey, default: 0] += 1
        lastErrorTimes[errorKey] = Date()
        
        // Add to history
        let entry = ErrorEntry(
            error: error,
            timestamp: Date(),
            context: context,
            recovered: false
        )
        
        errorHistory.insert(entry, at: 0)
        
        // Trim history
        if errorHistory.count > maxErrorHistorySize {
            errorHistory.removeLast(errorHistory.count - maxErrorHistorySize)
        }
    }
    
    private func recordRecovery(for error: any SnapzifyError, success: Bool) {
        if success {
            logger.info("Recovery successful for: \(String(describing: type(of: error)))")
            
            // Update last entry if it matches
            if let index = errorHistory.firstIndex(where: { 
                String(describing: type(of: $0.error)) == String(describing: type(of: error))
            }) {
                var entry = errorHistory[index]
                errorHistory[index] = ErrorEntry(
                    error: entry.error,
                    timestamp: entry.timestamp,
                    context: entry.context,
                    recovered: true
                )
            }
        } else {
            logger.error("Recovery failed for: \(String(describing: type(of: error)))")
        }
    }
    
    private func shouldThrottle(errorKey: String) -> Bool {
        guard let lastTime = lastErrorTimes[errorKey] else { return false }
        return Date().timeIntervalSince(lastTime) < errorThrottleInterval
    }
    
    private func findMostCriticalError(in errors: [Error]) -> Error? {
        // Prioritize non-recoverable errors
        return errors.first { error in
            if let snapzifyError = error as? any SnapzifyError {
                return !snapzifyError.isRecoverable
            }
            return false
        } ?? errors.first
    }
    
    private func attemptAutoRecovery(for error: any SnapzifyError) {
        let errorKey = String(describing: type(of: error))
        let errorCount = errorCounts[errorKey] ?? 0
        
        // Only auto-retry first 3 times
        if errorCount <= 3 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(errorCount) * 1_000_000_000)
                _ = await attemptRecovery(for: error)
            }
        }
    }
    
    // MARK: - Recovery Helpers
    
    private func checkNetworkConnectivity() async -> Bool {
        // Check network reachability
        // This is a simplified check - in production, use proper reachability monitoring
        do {
            let url = URL(string: "https://www.apple.com")!
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    private func checkStorageSpace() async -> Bool {
        // Check available storage
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory() as String)
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity > 100_000_000 // 100MB minimum
            }
        } catch {
            logger.error("Failed to check storage: \(error)")
        }
        return false
    }
    
    private func checkPermissions() async -> Bool {
        // Check necessary permissions (photo library, etc.)
        // Implementation depends on specific permissions needed
        return true
    }
    
    private func openSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }
    
    private func showSupportInfo() async {
        // Show support contact information
        logger.info("Support requested")
        // Implementation depends on support system
    }
    
    // MARK: - Cleanup
    
    /// Clear error history
    func clearHistory() {
        errorHistory.removeAll()
        errorCounts.removeAll()
        lastErrorTimes.removeAll()
        logger.info("Error history cleared")
    }
    
    /// Get error statistics
    func getStatistics() -> ErrorStatistics {
        ErrorStatistics(
            totalErrors: errorHistory.count,
            recoveredErrors: errorHistory.filter { $0.recovered }.count,
            errorCounts: errorCounts,
            mostRecentError: errorHistory.first
        )
    }
}

// MARK: - Error Statistics
struct ErrorStatistics {
    let totalErrors: Int
    let recoveredErrors: Int
    let errorCounts: [String: Int]
    let mostRecentError: ErrorRecoveryManager.ErrorEntry?
    
    var recoveryRate: Double {
        guard totalErrors > 0 else { return 0 }
        return Double(recoveredErrors) / Double(totalErrors)
    }
}

// MARK: - Generic Error Wrapper
struct GenericError: SnapzifyError {
    let underlyingError: Error?
    
    var errorDescription: String? {
        underlyingError?.localizedDescription ?? "An unknown error occurred"
    }
    
    var isRecoverable: Bool { true }
    var suggestedAction: ErrorRecoveryAction? { .retry }
}

// MARK: - Error Alert View Modifier
struct ErrorAlertModifier: ViewModifier {
    @StateObject private var errorManager = ErrorRecoveryManager.shared
    
    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: $errorManager.isShowingError,
                presenting: errorManager.currentError
            ) { error in
                if let action = error.suggestedAction {
                    Button(action.title) {
                        Task {
                            await errorManager.attemptRecovery(for: error)
                        }
                    }
                }
                Button("Dismiss", role: .cancel) {
                    errorManager.isShowingError = false
                }
            } message: { error in
                Text(error.localizedDescription)
            }
    }
}

extension View {
    func withErrorHandling() -> some View {
        modifier(ErrorAlertModifier())
    }
}