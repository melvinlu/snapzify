import Foundation
import Security

// MARK: - Keychain Service
/// Secure storage for sensitive data using iOS Keychain
@MainActor
class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.snapzify.app"
    private let accessGroup: String? = nil // Set if using app groups
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Save data securely to keychain
    func save(_ data: Data, for key: String) throws {
        let query = createQuery(for: key)
        
        // Delete existing item if present
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        var newQuery = query
        newQuery[kSecValueData as String] = data
        
        let status = SecItemAdd(newQuery as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Save string securely to keychain
    func saveString(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, for: key)
    }
    
    /// Save API key securely
    func saveAPIKey(_ apiKey: String, for service: APIService) throws {
        try saveString(apiKey, for: service.keychainKey)
    }
    
    /// Load data from keychain
    func load(key: String) throws -> Data {
        var query = createQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
    
    /// Load string from keychain
    func loadString(key: String) throws -> String {
        let data = try load(key: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }
    
    /// Load API key
    func loadAPIKey(for service: APIService) -> String? {
        try? loadString(key: service.keychainKey)
    }
    
    /// Delete item from keychain
    func delete(key: String) throws {
        let query = createQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    /// Delete API key
    func deleteAPIKey(for service: APIService) throws {
        try delete(key: service.keychainKey)
    }
    
    /// Check if key exists
    func exists(key: String) -> Bool {
        var query = createQuery(for: key)
        query[kSecReturnData as String] = false
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Delete all items for this app
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // MARK: - Private Methods
    
    private func createQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return query
    }
}

// MARK: - API Services
enum APIService: String, CaseIterable {
    case openAI = "OpenAI"
    case googleCloud = "GoogleCloud"
    case anthropic = "Anthropic"
    
    var keychainKey: String {
        "api_key_\(rawValue.lowercased())"
    }
    
    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .googleCloud: return "Google Cloud"
        case .anthropic: return "Anthropic"
        }
    }
}

// MARK: - Keychain Errors
enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(errorMessage(for: status))"
        case .loadFailed(let status):
            return "Failed to load from keychain: \(errorMessage(for: status))"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(errorMessage(for: status))"
        case .notFound:
            return "Item not found in keychain"
        case .invalidData:
            return "Invalid data format"
        }
    }
    
    private func errorMessage(for status: OSStatus) -> String {
        if let error = SecCopyErrorMessageString(status, nil) {
            return String(error)
        }
        return "Unknown error (\(status))"
    }
}

// MARK: - Secure Configuration Manager
/// Manages secure storage and retrieval of API configurations
class SecureConfigurationManager {
    static let shared = SecureConfigurationManager()
    
    private let keychain = KeychainService.shared
    private let userDefaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - API Key Management
    
    func setAPIKey(_ key: String?, for service: APIService) {
        guard let key = key, !key.isEmpty else {
            // Remove key if nil or empty
            try? keychain.deleteAPIKey(for: service)
            notifyConfigurationChanged(for: service)
            return
        }
        
        do {
            try keychain.saveAPIKey(key, for: service)
            notifyConfigurationChanged(for: service)
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to save API key for \(service.displayName)")
        }
    }
    
    func getAPIKey(for service: APIService) -> String? {
        keychain.loadAPIKey(for: service)
    }
    
    func hasAPIKey(for service: APIService) -> Bool {
        keychain.exists(key: service.keychainKey)
    }
    
    func removeAPIKey(for service: APIService) {
        try? keychain.deleteAPIKey(for: service)
        notifyConfigurationChanged(for: service)
    }
    
    // MARK: - Secure User Preferences
    
    func setSecurePreference<T: Codable>(_ value: T?, for key: String) {
        guard let value = value else {
            try? keychain.delete(key: "pref_\(key)")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            try keychain.save(data, for: "pref_\(key)")
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to save secure preference: \(key)")
        }
    }
    
    func getSecurePreference<T: Codable>(_ type: T.Type, for key: String) -> T? {
        do {
            let data = try keychain.load(key: "pref_\(key)")
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            if case KeychainError.notFound = error {
                // Not an error, just not set
                return nil
            }
            ErrorLogger.shared.log(error, context: "Failed to load secure preference: \(key)")
            return nil
        }
    }
    
    // MARK: - Configuration Export/Import
    
    struct ExportedConfiguration: Codable {
        let version: Int
        let exportDate: Date
        let settings: [String: String]
    }
    
    func exportConfiguration() -> ExportedConfiguration {
        var settings: [String: String] = [:]
        
        // Export non-sensitive settings only
        settings["selectedScript"] = userDefaults.string(forKey: "selectedScript")
        settings["autoTranslate"] = userDefaults.bool(forKey: "autoTranslate").description
        settings["autoGenerateAudio"] = userDefaults.bool(forKey: "autoGenerateAudio").description
        
        return ExportedConfiguration(
            version: 1,
            exportDate: Date(),
            settings: settings
        )
    }
    
    func importConfiguration(_ config: ExportedConfiguration) {
        for (key, value) in config.settings {
            switch key {
            case "selectedScript":
                userDefaults.set(value, forKey: key)
            case "autoTranslate", "autoGenerateAudio":
                userDefaults.set(Bool(value) ?? false, forKey: key)
            default:
                break
            }
        }
    }
    
    // MARK: - Security
    
    func clearAllSecureData() {
        do {
            try keychain.deleteAll()
        } catch {
            ErrorLogger.shared.log(error, context: "Failed to clear secure data", severity: .critical)
        }
    }
    
    private func notifyConfigurationChanged(for service: APIService) {
        NotificationCenter.default.post(
            name: Notification.Name("APIConfigurationChanged"),
            object: service
        )
    }
}

// MARK: - Migration from UserDefaults
extension SecureConfigurationManager {
    /// Migrate existing API keys from UserDefaults to Keychain
    func migrateFromUserDefaults() {
        let keysToMigrate = [
            ("openAIAPIKey", APIService.openAI),
            ("googleCloudAPIKey", APIService.googleCloud),
            ("anthropicAPIKey", APIService.anthropic)
        ]
        
        for (defaultsKey, service) in keysToMigrate {
            if let apiKey = userDefaults.string(forKey: defaultsKey),
               !apiKey.isEmpty {
                // Save to keychain
                setAPIKey(apiKey, for: service)
                
                // Remove from UserDefaults
                userDefaults.removeObject(forKey: defaultsKey)
            }
        }
        
        userDefaults.synchronize()
    }
}