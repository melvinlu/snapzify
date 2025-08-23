import Foundation
import AVFoundation

class TTSServiceOpenAI: TTSService {
    private let configService: ConfigService
    private let fileManager = FileManager.default
    private var audioDirectory: URL?
    
    init(configService: ConfigService) {
        self.configService = configService
        setupAudioDirectory()
    }
    
    private func setupAudioDirectory() {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.snapzify"
        ) else { return }
        
        let audioDir = containerURL.appendingPathComponent("Audio")
        
        if !fileManager.fileExists(atPath: audioDir.path) {
            try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        
        audioDirectory = audioDir
    }
    
    func isConfigured() -> Bool {
        guard let key = configService.openAIKey,
              !key.isEmpty,
              key != "REPLACE_WITH_YOUR_OPENAI_KEY" else {
            return false
        }
        return true
    }
    
    func generateAudio(for text: String, script: ChineseScript) async throws -> AudioAsset {
        guard isConfigured() else {
            throw TTSError.notConfigured
        }
        
        let voice = script == .simplified ? 
            configService.defaultVoiceSimplified : 
            configService.defaultVoiceTraditional
        
        let cacheKey = "\(text):\(voice):\(script.rawValue)".sha256()
        
        if let existingAsset = checkCache(for: cacheKey) {
            return existingAsset
        }
        
        let audioData = try await requestTTS(text: text, voice: voice)
        return try saveAudio(data: audioData, key: cacheKey)
    }
    
    private func checkCache(for key: String) -> AudioAsset? {
        guard let audioDir = audioDirectory else { return nil }
        
        let fileURL = audioDir.appendingPathComponent("\(key).m4a")
        
        if fileManager.fileExists(atPath: fileURL.path) {
            if let duration = getAudioDuration(url: fileURL) {
                return AudioAsset(sha: key, fileURL: fileURL, duration: duration)
            }
        }
        
        return nil
    }
    
    private func requestTTS(text: String, voice: String) async throws -> Data {
        guard let key = configService.openAIKey,
              let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw TTSError.invalidConfiguration
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": configService.ttsModel,
            "input": text,
            "voice": voice,
            "response_format": "aac",
            "speed": 1.0
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TTSError.requestFailed
        }
        
        return data
    }
    
    private func saveAudio(data: Data, key: String) throws -> AudioAsset {
        guard let audioDir = audioDirectory else {
            throw TTSError.noAudioDirectory
        }
        
        let fileURL = audioDir.appendingPathComponent("\(key).m4a")
        
        try data.write(to: fileURL)
        
        guard let duration = getAudioDuration(url: fileURL) else {
            throw TTSError.invalidAudioFile
        }
        
        return AudioAsset(sha: key, fileURL: fileURL, duration: duration)
    }
    
    private func getAudioDuration(url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        
        guard duration.flags.contains(.valid) else { return nil }
        
        return CMTimeGetSeconds(duration)
    }
}

enum TTSError: Error {
    case notConfigured
    case invalidConfiguration
    case requestFailed
    case noAudioDirectory
    case invalidAudioFile
}