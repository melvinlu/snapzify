import Foundation
import Security

class ConfigServiceImpl: ConfigService {
    private var config: SnapzifyConfig
    private let keychainService = "com.snapzify.api"
    private let keychainAccount = "openai"
    
    var openAIKey: String? {
        if let keychainKey = getKeyFromKeychain() {
            return keychainKey
        }
        return config.openai.apiKey.isEmpty || 
               config.openai.apiKey == "REPLACE_WITH_YOUR_OPENAI_KEY" ? nil : config.openai.apiKey
    }
    
    var translationModel: String { config.openai.translationModel }
    var ttsModel: String { config.openai.ttsModel }
    var defaultVoiceSimplified: String { config.openai.defaultVoiceSimplified }
    var defaultVoiceTraditional: String { config.openai.defaultVoiceTraditional }
    var requestsPerBatch: Int { config.openai.requestsPerBatch }
    var cloudTranslationEnabledDefault: Bool { config.features.cloudTranslationEnabledDefault }
    var cloudAudioEnabledDefault: Bool { config.features.cloudAudioEnabledDefault }
    
    init() {
        if let url = Bundle.main.url(forResource: "SnapzifyConfig", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SnapzifyConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = SnapzifyConfig.default
        }
    }
    
    func updateAPIKey(_ key: String?) {
        if let key = key {
            saveKeyToKeychain(key)
        } else {
            deleteKeyFromKeychain()
        }
    }
    
    private func getKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    private func saveKeyToKeychain(_ key: String) {
        deleteKeyFromKeychain()
        
        guard let data = key.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

struct SnapzifyConfig: Codable {
    let openai: OpenAIConfig
    let features: FeaturesConfig
    
    struct OpenAIConfig: Codable {
        let apiKey: String
        let translationModel: String
        let ttsModel: String
        let defaultVoiceSimplified: String
        let defaultVoiceTraditional: String
        let requestsPerBatch: Int
    }
    
    struct FeaturesConfig: Codable {
        let cloudTranslationEnabledDefault: Bool
        let cloudAudioEnabledDefault: Bool
    }
    
    static let `default` = SnapzifyConfig(
        openai: OpenAIConfig(
            apiKey: "REPLACE_WITH_YOUR_OPENAI_KEY",
            translationModel: "gpt-4o-mini",
            ttsModel: "tts-1",
            defaultVoiceSimplified: "alloy",
            defaultVoiceTraditional: "nova",
            requestsPerBatch: 12
        ),
        features: FeaturesConfig(
            cloudTranslationEnabledDefault: true,
            cloudAudioEnabledDefault: true
        )
    )
}