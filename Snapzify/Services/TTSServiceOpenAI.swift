import Foundation
import AVFoundation
import SwiftUI
import CryptoKit

class TTSServiceOpenAI: TTSService {
    private let configService: ConfigService
    private let fileManager = FileManager.default
    private var audioDirectory: URL?
    
    @AppStorage("ttsSpeed") private var ttsSpeed: Double = 1.0
    @AppStorage("voiceSimplified") private var voiceSimplified: String = "alloy"
    @AppStorage("voiceTraditional") private var voiceTraditional: String = "nova"
    
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
        let hasKey = configService.openAIKey != nil
        let keyNotEmpty = !(configService.openAIKey?.isEmpty ?? true)
        let keyNotDefault = configService.openAIKey != "REPLACE_WITH_YOUR_OPENAI_KEY"
        
        print("TTSService: Configuration check - hasKey: \(hasKey), keyNotEmpty: \(keyNotEmpty), keyNotDefault: \(keyNotDefault)")
        
        guard let key = configService.openAIKey,
              !key.isEmpty,
              key != "REPLACE_WITH_YOUR_OPENAI_KEY" else {
            print("TTSService: TTS service not properly configured")
            return false
        }
        print("TTSService: TTS service properly configured")
        return true
    }
    
    func generateAudio(for text: String, script: ChineseScript) async throws -> AudioAsset {
        print("TTSService: generateAudio called for text: '\(text.prefix(50))...'")
        print("TTSService: Script: \(script), isConfigured: \(isConfigured())")
        
        guard isConfigured() else {
            print("TTSService: TTS service not configured")
            throw TTSError.notConfigured
        }
        
        // Use user's voice settings instead of config defaults
        let voice = script == .simplified ? voiceSimplified : voiceTraditional
        let speed = ttsSpeed
        
        print("TTSService: Using voice: \(voice), speed: \(speed)")
        
        let cacheKey = "\(text):\(voice):\(speed):\(script.rawValue)".sha256()
        print("TTSService: Cache key: \(cacheKey.prefix(16))...")
        
        if let existingAsset = checkCache(for: cacheKey) {
            print("TTSService: Found cached audio asset")
            return existingAsset
        }
        
        print("TTSService: No cache found, making API request")
        let audioData = try await requestTTS(text: text, voice: voice, speed: speed)
        print("TTSService: Received audio data, size: \(audioData.count) bytes")
        
        let savedAsset = try saveAudio(data: audioData, key: cacheKey)
        print("TTSService: Audio saved to: \(savedAsset.fileURL)")
        return savedAsset
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
    
    private func requestTTS(text: String, voice: String, speed: Double) async throws -> Data {
        print("TTSService: Making TTS request with voice: \(voice), speed: \(speed)")
        
        guard let key = configService.openAIKey,
              let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            print("TTSService: Invalid configuration - missing API key or URL")
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
            "speed": speed
        ]
        
        print("TTSService: Request payload - model: \(configService.ttsModel), voice: \(voice), speed: \(speed), format: aac")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            print("TTSService: Request body created, size: \(request.httpBody?.count ?? 0) bytes")
        } catch {
            print("TTSService: Failed to serialize request payload: \(error)")
            throw error
        }
        
        print("TTSService: Sending request to OpenAI TTS API...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("TTSService: Invalid response type")
            throw TTSError.requestFailed
        }
        
        print("TTSService: Received response with status code: \(httpResponse.statusCode)")
        print("TTSService: Response data size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            print("TTSService: API request failed with status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("TTSService: Error response: \(responseString)")
            }
            throw TTSError.requestFailed
        }
        
        print("TTSService: TTS request completed successfully")
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