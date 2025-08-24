import Foundation
import AVFoundation
import SwiftUI
import CryptoKit
import os.log

class TTSServiceOpenAI: TTSService {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "TTSService")
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
            forSecurityApplicationGroupIdentifier: "group.com.snapzify.app"
        ) else { 
            print("TTSService: Failed to get container URL for group.com.snapzify.app")
            return 
        }
        
        let audioDir = containerURL.appendingPathComponent("Audio")
        
        do {
            if !fileManager.fileExists(atPath: audioDir.path) {
                try fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
                print("TTSService: Created audio directory at \(audioDir.path)")
            }
            audioDirectory = audioDir
            print("TTSService: Audio directory set to \(audioDir.path)")
        } catch {
            print("TTSService: Failed to create audio directory: \(error)")
        }
    }
    
    func isConfigured() -> Bool {
        let hasKey = configService.openAIKey != nil
        let keyNotEmpty = !(configService.openAIKey?.isEmpty ?? true)
        let keyNotDefault = configService.openAIKey != "REPLACE_WITH_YOUR_OPENAI_KEY"
        
        logger.debug("Configuration check - hasKey: \(hasKey), keyNotEmpty: \(keyNotEmpty), keyNotDefault: \(keyNotDefault)")
        
        guard let key = configService.openAIKey,
              !key.isEmpty,
              key != "REPLACE_WITH_YOUR_OPENAI_KEY" else {
            logger.warning("TTS service not properly configured")
            return false
        }
        logger.debug("TTS service properly configured")
        return true
    }
    
    func generateAudio(for text: String, script: ChineseScript) async throws -> AudioAsset {
        logger.info("generateAudio called for text: '\(text.prefix(50))...'")
        let configured = isConfigured()
        logger.debug("Script: \(script.rawValue), isConfigured: \(configured)")
        
        guard configured else {
            logger.warning("TTS service not configured")
            throw TTSError.notConfigured
        }
        
        // Use user's voice settings instead of config defaults
        let voice = script == .simplified ? voiceSimplified : voiceTraditional
        let speed = ttsSpeed
        
        logger.debug("Using voice: \(voice), speed: \(speed)")
        
        let cacheKey = "\(text):\(voice):\(speed):\(script.rawValue)".sha256()
        logger.debug("Cache key: \(cacheKey.prefix(16))...")
        
        if let existingAsset = checkCache(for: cacheKey) {
            logger.debug("Found cached audio asset")
            return existingAsset
        }
        
        logger.debug("No cache found, making API request")
        let audioData = try await requestTTS(text: text, voice: voice, speed: speed)
        logger.info("Received audio data, size: \(audioData.count) bytes")
        
        let savedAsset = try saveAudio(data: audioData, key: cacheKey)
        logger.info("Audio saved to: \(savedAsset.fileURL)")
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
        logger.debug("Making TTS request with voice: \(voice), speed: \(speed)")
        
        guard let key = configService.openAIKey,
              let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            logger.error("Invalid configuration - missing API key or URL")
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
        
        logger.debug("Request payload - model: \(self.configService.ttsModel), voice: \(voice), speed: \(speed), format: aac")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            logger.debug("Request body created, size: \(request.httpBody?.count ?? 0) bytes")
        } catch {
            logger.error("Failed to serialize request payload: \(error)")
            throw error
        }
        
        logger.debug("Sending request to OpenAI TTS API...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type")
            throw TTSError.requestFailed
        }
        
        logger.info("Received response with status code: \(httpResponse.statusCode)")
        logger.debug("Response data size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("API request failed with status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.error("Error response: \(responseString)")
            }
            throw TTSError.requestFailed
        }
        
        logger.debug("TTS request completed successfully")
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