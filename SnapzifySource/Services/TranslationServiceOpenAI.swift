import Foundation

class TranslationServiceOpenAI: TranslationService {
    private let configService: ConfigService
    private let cache = NSCache<NSString, NSString>()
    private let semaphore = DispatchSemaphore(value: 3)
    
    init(configService: ConfigService) {
        self.configService = configService
        cache.countLimit = 500
    }
    
    func isConfigured() -> Bool {
        guard let key = configService.openAIKey,
              !key.isEmpty,
              key != "REPLACE_WITH_YOUR_OPENAI_KEY" else {
            return false
        }
        return true
    }
    
    func translate(_ sentences: [String]) async throws -> [String?] {
        guard isConfigured() else {
            throw TranslationError.notConfigured
        }
        
        var results: [String?] = Array(repeating: nil, count: sentences.count)
        
        let chunks = sentences.chunked(into: configService.requestsPerBatch)
        
        try await withThrowingTaskGroup(of: (Int, [String?]).self) { group in
            for (chunkIndex, chunk) in chunks.enumerated() {
                group.addTask {
                    let translations = try await self.translateBatch(chunk)
                    return (chunkIndex, translations)
                }
            }
            
            for try await (chunkIndex, translations) in group {
                let startIndex = chunkIndex * configService.requestsPerBatch
                for (i, translation) in translations.enumerated() {
                    results[startIndex + i] = translation
                }
            }
        }
        
        return results
    }
    
    private func translateBatch(_ sentences: [String]) async throws -> [String?] {
        var translations: [String?] = []
        
        for sentence in sentences {
            let cacheKey = sentence.sha256() as NSString
            
            if let cached = cache.object(forKey: cacheKey) {
                translations.append(cached as String)
                continue
            }
            
            let translation = try await translateSingle(sentence)
            if let translation = translation {
                cache.setObject(translation as NSString, forKey: cacheKey)
            }
            translations.append(translation)
        }
        
        return translations
    }
    
    private func translateSingle(_ text: String) async throws -> String? {
        guard let key = configService.openAIKey,
              let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw TranslationError.invalidConfiguration
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": configService.translationModel,
            "messages": [
                ["role": "system", "content": "You are a translator. Translate the following Chinese text to English. Respond only with the translation."],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 150
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        await withCheckedContinuation { continuation in
            semaphore.wait()
            continuation.resume()
        }
        
        defer { semaphore.signal() }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }
        
        if httpResponse.statusCode == 429 {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return try await translateSingle(text)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw TranslationError.httpError(httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String
        
        return content?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranslationError: Error {
    case notConfigured
    case invalidConfiguration
    case invalidResponse
    case httpError(Int)
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}


import CryptoKit

extension String {
    func sha256() -> String {
        let data = Data(utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}