import Foundation
import SwiftUI

// MARK: - Application Error Types
protocol SnapzifyError: LocalizedError {
    var isRecoverable: Bool { get }
    var suggestedAction: ErrorRecoveryAction? { get }
    var underlyingError: Error? { get }
}

// MARK: - Error Recovery Actions
enum ErrorRecoveryAction {
    case retry
    case checkNetwork
    case checkStorage
    case checkPermissions
    case configureSettings
    case contactSupport
    
    var title: String {
        switch self {
        case .retry: return "Retry"
        case .checkNetwork: return "Check Connection"
        case .checkStorage: return "Free Up Space"
        case .checkPermissions: return "Check Permissions"
        case .configureSettings: return "Open Settings"
        case .contactSupport: return "Get Help"
        }
    }
    
    var icon: String {
        switch self {
        case .retry: return "arrow.clockwise"
        case .checkNetwork: return "wifi.exclamationmark"
        case .checkStorage: return "internaldrive"
        case .checkPermissions: return "lock.shield"
        case .configureSettings: return "gear"
        case .contactSupport: return "questionmark.circle"
        }
    }
}

// MARK: - Media Processing Errors
enum MediaProcessingError: SnapzifyError {
    case fileNotFound(URL)
    case invalidFormat(String)
    case processingFailed(String)
    case memoryLimitExceeded
    case cancelled
    case thumbnailGenerationFailed
    case unsupportedMediaType
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found at \(url.lastPathComponent)"
        case .invalidFormat(let format):
            return "Invalid format: \(format)"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        case .memoryLimitExceeded:
            return "File too large to process. Try a smaller file."
        case .cancelled:
            return "Processing was cancelled"
        case .thumbnailGenerationFailed:
            return "Could not generate thumbnail"
        case .unsupportedMediaType:
            return "This media type is not supported"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .cancelled, .memoryLimitExceeded:
            return false
        default:
            return true
        }
    }
    
    var suggestedAction: ErrorRecoveryAction? {
        switch self {
        case .memoryLimitExceeded:
            return .checkStorage
        case .cancelled:
            return nil
        default:
            return .retry
        }
    }
    
    var underlyingError: Error? { nil }
}

// MARK: - Storage Errors
enum StorageError: SnapzifyError {
    case insufficientSpace
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)
    case corruptedData
    case migrationFailed
    
    var errorDescription: String? {
        switch self {
        case .insufficientSpace:
            return "Not enough storage space available"
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete: \(error.localizedDescription)"
        case .corruptedData:
            return "Data appears to be corrupted"
        case .migrationFailed:
            return "Failed to migrate data to new format"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .corruptedData, .migrationFailed:
            return false
        default:
            return true
        }
    }
    
    var suggestedAction: ErrorRecoveryAction? {
        switch self {
        case .insufficientSpace:
            return .checkStorage
        case .corruptedData, .migrationFailed:
            return .contactSupport
        default:
            return .retry
        }
    }
    
    var underlyingError: Error? {
        switch self {
        case .saveFailed(let error), .loadFailed(let error), .deleteFailed(let error):
            return error
        default:
            return nil
        }
    }
}

// MARK: - Network Errors
enum NetworkError: SnapzifyError {
    case noConnection
    case timeout
    case invalidResponse
    case serverError(Int)
    case rateLimited
    case apiKeyInvalid
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error (code: \(code))"
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .apiKeyInvalid:
            return "API key is invalid or expired"
        case .quotaExceeded:
            return "API quota exceeded"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .apiKeyInvalid, .quotaExceeded:
            return false
        default:
            return true
        }
    }
    
    var suggestedAction: ErrorRecoveryAction? {
        switch self {
        case .noConnection, .timeout:
            return .checkNetwork
        case .apiKeyInvalid:
            return .configureSettings
        case .rateLimited:
            return .retry
        default:
            return nil
        }
    }
    
    var underlyingError: Error? { nil }
}

// MARK: - Permission Errors
enum PermissionError: SnapzifyError {
    case photoLibraryDenied
    case cameraAccessDenied
    case microphoneAccessDenied
    case notificationsDenied
    
    var errorDescription: String? {
        switch self {
        case .photoLibraryDenied:
            return "Photo library access denied"
        case .cameraAccessDenied:
            return "Camera access denied"
        case .microphoneAccessDenied:
            return "Microphone access denied"
        case .notificationsDenied:
            return "Notifications disabled"
        }
    }
    
    var isRecoverable: Bool { true }
    
    var suggestedAction: ErrorRecoveryAction? { .checkPermissions }
    
    var underlyingError: Error? { nil }
}

// MARK: - Error Recovery Manager
@MainActor
class ErrorRecoveryManager: ObservableObject {
    static let shared = ErrorRecoveryManager()
    
    @Published var currentError: (any SnapzifyError)?
    @Published var isShowingError = false
    
    private var retryHandlers: [String: () async throws -> Void] = [:]
    
    private init() {}
    
    func handle(
        _ error: any SnapzifyError,
        retryHandler: (() async throws -> Void)? = nil
    ) {
        currentError = error
        isShowingError = true
        
        if let handler = retryHandler {
            let errorId = UUID().uuidString
            retryHandlers[errorId] = handler
            
            // Clean up after 5 minutes
            Task {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                retryHandlers.removeValue(forKey: errorId)
            }
        }
    }
    
    func performRecoveryAction(_ action: ErrorRecoveryAction) async {
        switch action {
        case .retry:
            if let errorId = retryHandlers.keys.first,
               let handler = retryHandlers[errorId] {
                do {
                    try await handler()
                    clearError()
                } catch {
                    print("Retry failed: \(error)")
                }
            }
            
        case .checkNetwork:
            // Open system settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            
        case .checkStorage:
            // Could show storage usage
            clearError()
            
        case .checkPermissions:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            
        case .configureSettings:
            // Navigate to app settings
            clearError()
            
        case .contactSupport:
            // Open support URL
            if let url = URL(string: "https://github.com/anthropics/claude-code/issues") {
                await UIApplication.shared.open(url)
            }
        }
    }
    
    func clearError() {
        currentError = nil
        isShowingError = false
        retryHandlers.removeAll()
    }
}

// MARK: - Error Alert View Modifier
struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorManager = ErrorRecoveryManager.shared
    
    func body(content: Content) -> some View {
        content
            .alert(
                "Error",
                isPresented: $errorManager.isShowingError
            ) {
                if let error = errorManager.currentError {
                    if let action = error.suggestedAction {
                        Button(action.title) {
                            Task {
                                await errorManager.performRecoveryAction(action)
                            }
                        }
                    }
                    
                    Button("Dismiss", role: .cancel) {
                        errorManager.clearError()
                    }
                }
            } message: {
                if let error = errorManager.currentError {
                    Text(error.localizedDescription)
                }
            }
    }
}

extension View {
    func errorAlert() -> some View {
        modifier(ErrorAlertModifier())
    }
}

// MARK: - Error Logger
class ErrorLogger {
    static let shared = ErrorLogger()
    
    private let logQueue = DispatchQueue(label: "com.snapzify.errorlogger")
    private var errorLog: [ErrorLogEntry] = []
    private let maxLogEntries = 100
    
    struct ErrorLogEntry {
        let timestamp: Date
        let error: String
        let context: String?
        let severity: Severity
        
        enum Severity: String {
            case debug, info, warning, error, critical
        }
    }
    
    private init() {}
    
    func log(
        _ error: Error,
        context: String? = nil,
        severity: ErrorLogEntry.Severity = .error
    ) {
        let entry = ErrorLogEntry(
            timestamp: Date(),
            error: error.localizedDescription,
            context: context,
            severity: severity
        )
        
        logQueue.async { [weak self] in
            self?.errorLog.append(entry)
            
            // Keep only recent entries
            if let self = self, self.errorLog.count > self.maxLogEntries {
                self.errorLog.removeFirst(self.errorLog.count - self.maxLogEntries)
            }
        }
        
        #if DEBUG
        print("[\(severity.rawValue.uppercased())] \(error.localizedDescription)")
        if let context = context {
            print("Context: \(context)")
        }
        #endif
    }
    
    func getRecentErrors(count: Int = 10) -> [ErrorLogEntry] {
        logQueue.sync {
            Array(errorLog.suffix(count))
        }
    }
    
    func clearLogs() {
        logQueue.async { [weak self] in
            self?.errorLog.removeAll()
        }
    }
}