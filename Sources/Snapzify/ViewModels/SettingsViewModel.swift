import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid = false
    @Published var isSaving = false
    @Published var showAPIKeySaved = false
    
    @AppStorage("selectedScript") var selectedScript: String = ChineseScript.simplified.rawValue
    @AppStorage("autoTranslate") var autoTranslate = true
    @AppStorage("autoGenerateAudio") var autoGenerateAudio = true
    @AppStorage("ttsSpeed") var ttsSpeed: Double = 1.0
    @AppStorage("voiceSimplified") var voiceSimplified: String = "alloy"
    @AppStorage("voiceTraditional") var voiceTraditional: String = "nova"
    
    private let configService: ConfigService
    private let translationService: TranslationService
    private let ttsService: TTSService
    
    var currentScript: ChineseScript {
        get { ChineseScript(rawValue: selectedScript) ?? .simplified }
        set { selectedScript = newValue.rawValue }
    }
    
    var translationStatus: String {
        if translationService.isConfigured() {
            return "Active"
        } else if apiKey.isEmpty {
            return "No API Key"
        } else {
            return "Invalid Key"
        }
    }
    
    var audioStatus: String {
        if ttsService.isConfigured() {
            return "Active"
        } else if apiKey.isEmpty {
            return "No API Key"
        } else {
            return "Invalid Key"
        }
    }
    
    let availableVoices = [
        "alloy": "Alloy (Neutral)",
        "echo": "Echo (Male)",
        "fable": "Fable (British)",
        "onyx": "Onyx (Male)",
        "nova": "Nova (Female)",
        "shimmer": "Shimmer (Female)"
    ]
    
    init(
        configService: ConfigService,
        translationService: TranslationService,
        ttsService: TTSService
    ) {
        self.configService = configService
        self.translationService = translationService
        self.ttsService = ttsService
        
        loadCurrentAPIKey()
    }
    
    func loadCurrentAPIKey() {
        if let key = configService.openAIKey {
            apiKey = key
            isAPIKeyValid = true
        }
    }
    
    func saveAPIKey() {
        guard !apiKey.isEmpty else { return }
        
        isSaving = true
        
        Task {
            defer { isSaving = false }
            
            configService.updateAPIKey(apiKey)
            
            await MainActor.run {
                isAPIKeyValid = true
                showAPIKeySaved = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.showAPIKeySaved = false
                }
            }
        }
    }
    
    func clearAPIKey() {
        apiKey = ""
        isAPIKeyValid = false
        configService.updateAPIKey(nil)
    }
    
    func testAPIKey() async {
        guard !apiKey.isEmpty else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        configService.updateAPIKey(apiKey)
        
        do {
            let testResult = try await translationService.translate(["测试"])
            isAPIKeyValid = !testResult.isEmpty
        } catch {
            isAPIKeyValid = false
        }
    }
}