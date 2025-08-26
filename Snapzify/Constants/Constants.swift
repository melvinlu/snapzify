import Foundation
import UIKit

// MARK: - App Constants
enum Constants {
    
    // MARK: - Media Processing
    enum Media {
        static let frameExtractionInterval: TimeInterval = 0.2
        static let maxVideoFramesToProcess = 500
        static let thumbnailSize = CGSize(width: 120, height: 120)
        static let largeImageMaxDimension: CGFloat = 4000
        static let videoCompressionQuality = 0.7
        static let imageCompressionQuality = 0.9
    }
    
    // MARK: - Cache Limits
    enum Cache {
        static let maxImageCacheSize = 50_000_000 // 50MB
        static let maxImageCacheCount = 20
        static let maxDocumentCacheSize = 20_000_000 // 20MB
        static let maxDocumentCacheCount = 30
        static let maxThumbnailCacheSize = 10_000_000 // 10MB
        static let maxThumbnailCacheCount = 100
        static let cacheExpirationDays = 7
    }
    
    // MARK: - UI Dimensions
    enum UI {
        static let buttonHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 16
        static let smallCornerRadius: CGFloat = 8
        static let shadowRadius: CGFloat = 20
        static let shadowOpacity: Float = 0.2
        static let popupMaxWidth: CGFloat = 340
        static let popupMaxHeight: CGFloat = 600
        static let chatGPTPopupMaxWidth: CGFloat = 400
        static let navigationButtonSize: CGFloat = 44
    }
    
    // MARK: - Animation Durations
    enum Animation {
        static let quick: TimeInterval = 0.2
        static let normal: TimeInterval = 0.3
        static let slow: TimeInterval = 0.5
        static let spring: (response: Double, dampingFraction: Double) = (0.3, 0.8)
    }
    
    // MARK: - Networking
    enum Network {
        static let requestTimeout: TimeInterval = 30
        static let uploadTimeout: TimeInterval = 120
        static let maxRetries = 3
        static let retryDelay: TimeInterval = 1.0
    }
    
    // MARK: - Text Processing
    enum TextProcessing {
        static let minSentenceLength = 1
        static let maxSentenceLength = 500
        static let batchTranslationSize = 10
        static let translationTimeout: TimeInterval = 60
    }
    
    // MARK: - Audio
    enum Audio {
        static let defaultPlaybackRate: Float = 1.0
        static let slowPlaybackRate: Float = 0.7
        static let fastPlaybackRate: Float = 1.5
        static let audioGenerationTimeout: TimeInterval = 30
    }
    
    // MARK: - Storage
    enum Storage {
        static let documentsDirectoryName = "Documents"
        static let mediaDirectoryName = "Media"
        static let thumbnailDirectoryName = "Thumbnails"
        static let cacheDirectoryName = "MediaCache"
        static let audioDirectoryName = "Audio"
    }
    
    // MARK: - Pagination
    enum Pagination {
        static let defaultPageSize = 20
        static let preloadThreshold = 5
    }
    
    // MARK: - Performance
    enum Performance {
        static let concurrentOperationLimit = 4
        static let backgroundTaskIdentifier = "com.snapzify.background-processing"
        static let refreshInterval: TimeInterval = 1.0
    }
    
    // MARK: - File Extensions
    enum FileExtension {
        static let image = "jpg"
        static let video = "mov"
        static let thumbnail = "_thumb.jpg"
        static let audio = "m4a"
    }
    
    // MARK: - Error Messages
    enum ErrorMessage {
        static let genericError = "An error occurred. Please try again."
        static let networkError = "Network connection error. Please check your internet connection."
        static let processingError = "Failed to process media. Please try again."
        static let storageError = "Failed to save document. Please check available storage."
        static let authorizationError = "Photo library access denied. Please enable in Settings."
        static let apiKeyMissing = "Please configure your API key in Settings."
    }
    
    // MARK: - Notification Names
    enum NotificationName {
        static let documentSavedStatusChanged = "documentSavedStatusChanged"
        static let processingCompleted = "processingCompleted"
        static let memoryWarning = "memoryWarning"
        static let cacheCleared = "cacheCleared"
    }
    
    // MARK: - User Defaults Keys
    enum UserDefaultsKey {
        static let autoTranslate = "autoTranslate"
        static let autoGenerateAudio = "autoGenerateAudio"
        static let selectedScript = "selectedScript"
        static let openAIAPIKey = "openAIAPIKey"
        static let hasShownOnboarding = "hasShownOnboarding"
        static let lastCacheClearDate = "lastCacheClearDate"
    }
    
    // MARK: - API Endpoints
    enum API {
        static let openAICompletions = "https://api.openai.com/v1/chat/completions"
        static let openAIAudio = "https://api.openai.com/v1/audio/speech"
    }
    
    // MARK: - Debug
    enum Debug {
        static let enableDetailedLogging = false
        static let mockAPIResponses = false
        static let simulateSlowNetwork = false
    }
}