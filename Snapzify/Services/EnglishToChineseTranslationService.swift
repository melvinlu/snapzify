import Foundation

// MARK: - Models
struct ChineseTranslation: Codable, Hashable {
    let chinese: String
    let pinyin: String
    let context: String
    let usage: String
    let formality: String // formal, informal, neutral
}

class TranslationResult: NSObject, Codable {
    let query: String
    let translations: [ChineseTranslation]
    let timestamp: Date
    
    init(query: String, translations: [ChineseTranslation], timestamp: Date) {
        self.query = query
        self.translations = translations
        self.timestamp = timestamp
        super.init()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.query = try container.decode(String.self, forKey: .query)
        self.translations = try container.decode([ChineseTranslation].self, forKey: .translations)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        super.init()
    }
    
    private enum CodingKeys: String, CodingKey {
        case query, translations, timestamp
    }
}

// MARK: - Protocol
protocol EnglishToChineseTranslationService {
    func translate(_ englishText: String) async throws -> TranslationResult
    func streamTranslate(_ englishText: String) -> AsyncThrowingStream<String, Error>
    func streamBreakdown(_ chineseText: String) -> AsyncThrowingStream<String, Error>
    func streamAsk(_ question: String) -> AsyncThrowingStream<String, Error>
    func streamAskWithHistory(_ question: String, history: [String]) -> AsyncThrowingStream<String, Error>
    func streamPronunciationFeedback(_ transcription: String) -> AsyncThrowingStream<String, Error>
    func isConfigured() -> Bool
    func clearCache()
}

// MARK: - Implementation
class EnglishToChineseTranslationServiceImpl: EnglishToChineseTranslationService {
    private let configService: ConfigService
    private let cache = NSCache<NSString, TranslationResult>()
    private let diskCache: URL?
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    init(configService: ConfigService) {
        self.configService = configService
        cache.countLimit = 100
        
        // Setup disk cache
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            diskCache = cacheDir.appendingPathComponent("EnglishChineseTranslations")
            try? FileManager.default.createDirectory(at: diskCache!, withIntermediateDirectories: true)
        } else {
            diskCache = nil
        }
        
        // Load disk cache into memory
        loadDiskCache()
    }
    
    func isConfigured() -> Bool {
        guard let key = configService.openAIKey,
              !key.isEmpty,
              key != "REPLACE_WITH_YOUR_OPENAI_KEY" else {
            return false
        }
        return true
    }
    
    func streamAskWithHistory(_ question: String, history: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isConfigured() else {
                        throw EnglishChineseTranslationError.notConfigured
                    }
                    
                    let trimmedText = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedText.isEmpty else {
                        throw EnglishChineseTranslationError.invalidInput("Empty input text")
                    }
                    
                    guard let key = configService.openAIKey,
                          let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        throw EnglishChineseTranslationError.invalidConfiguration
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let systemPrompt = """
                    You are a native Chinese language expert with deep knowledge of Chinese language, culture, idioms, and colloquial expressions.
                    
                    Answer questions about Chinese language and culture in a helpful, clear, and concise manner.
                    Provide examples when helpful, using Chinese characters with pinyin when relevant.
                    Be direct and practical in your responses.
                    
                    No headers, labels, or unnecessary formatting. Just provide clear, helpful answers.
                    """
                    
                    // Build messages array with history
                    var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
                    
                    // Add conversation history
                    for item in history {
                        if item.hasPrefix("Q: ") {
                            messages.append(["role": "user", "content": String(item.dropFirst(3))])
                        } else if item.hasPrefix("A: ") {
                            messages.append(["role": "assistant", "content": String(item.dropFirst(3))])
                        }
                    }
                    
                    // Add current question
                    messages.append(["role": "user", "content": trimmedText])
                    
                    let payload: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": messages,
                        "stream": true,
                        "temperature": 0.3
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                break
                            }
                            
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first,
                               let delta = first["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func streamAsk(_ question: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isConfigured() else {
                        throw EnglishChineseTranslationError.notConfigured
                    }
                    
                    let trimmedText = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedText.isEmpty else {
                        throw EnglishChineseTranslationError.invalidInput("Empty input text")
                    }
                    
                    guard let key = configService.openAIKey,
                          let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        throw EnglishChineseTranslationError.invalidConfiguration
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let systemPrompt = """
                    You are a native Chinese language expert with deep knowledge of Chinese language, culture, idioms, and colloquial expressions.
                    
                    Answer questions about Chinese language and culture in a helpful, clear, and concise manner.
                    Provide examples when helpful, using Chinese characters with pinyin when relevant.
                    Be direct and practical in your responses.
                    
                    No headers, labels, or unnecessary formatting. Just provide clear, helpful answers.
                    """
                    
                    let userPrompt = trimmedText
                    
                    let payload: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userPrompt]
                        ],
                        "stream": true,
                        "temperature": 0.3
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                break
                            }
                            
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first,
                               let delta = first["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func streamPronunciationFeedback(_ transcription: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isConfigured() else {
                        throw EnglishChineseTranslationError.notConfigured
                    }
                    
                    guard let key = configService.openAIKey,
                          let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        throw EnglishChineseTranslationError.invalidConfiguration
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let systemPrompt = """
                    You are a native Chinese speaker and language teacher. You're listening to someone practicing Chinese pronunciation.
                    
                    Based on the transcription, provide feedback:
                    
                    First line: Just the English translation of what was said. Nothing else. No "What I heard was" or "The student said" or any other preamble. Just the direct English meaning.
                    
                    After a blank line, provide feedback in Chinese on whether it was a natural way to express it.
                    
                    Be encouraging but honest. If the pronunciation was unclear or the phrasing unnatural, suggest improvements.
                    Keep your response concise and practical. Do not use numbered lists or bullet points.
                    """
                    
                    let userPrompt = "The student said: \"\(transcription)\""
                    
                    let payload: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userPrompt]
                        ],
                        "stream": true,
                        "temperature": 0.3
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                break
                            }
                            
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first,
                               let delta = first["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func streamBreakdown(_ chineseText: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isConfigured() else {
                        throw EnglishChineseTranslationError.notConfigured
                    }
                    
                    let trimmedText = chineseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedText.isEmpty else {
                        throw EnglishChineseTranslationError.invalidInput("Empty input text")
                    }
                    
                    guard let key = configService.openAIKey,
                          let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        throw EnglishChineseTranslationError.invalidConfiguration
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let systemPrompt = """
                    You are a Chinese language expert. Provide a detailed breakdown of the given Chinese text.
                    
                    First, provide the overall meaning of the complete text.
                    
                    Then break down each character individually with:
                    - The character
                    - Pinyin
                    - Meaning(s)
                    - Any relevant notes about usage
                    
                    Be concise and direct. No headers, labels, or unnecessary formatting. Just provide the breakdown information.
                    
                    Format:
                    [complete translation/meaning]
                    
                    [character] • [pinyin] • [meaning/explanation]
                    [character] • [pinyin] • [meaning/explanation]
                    [continue for each character]
                    """
                    
                    let userPrompt = "Break down this Chinese text: \"\(trimmedText)\""
                    
                    let payload: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userPrompt]
                        ],
                        "stream": true,
                        "temperature": 0.3
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if jsonString == "[DONE]" {
                                break
                            }
                            
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first,
                               let delta = first["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func streamTranslate(_ englishText: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard isConfigured() else {
                        throw EnglishChineseTranslationError.notConfigured
                    }
                    
                    let trimmedText = englishText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedText.isEmpty else {
                        throw EnglishChineseTranslationError.invalidInput("Empty input text")
                    }
                    
                    guard let key = configService.openAIKey,
                          let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        throw EnglishChineseTranslationError.invalidConfiguration
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let systemPrompt = """
                    You are a professional English-to-Chinese translator specializing in colloquial and everyday language. For the given English word or phrase, provide Chinese translations that are commonly used in casual conversation and daily life.
                    
                    PRIORITIZE colloquial usage over formal or literary translations. Rank translations by how frequently they appear in everyday spoken Chinese, with the most colloquial and commonly used translation first.
                    
                    DO NOT include any header, introduction, brackets, or horizontal rules. Start directly with the translations.
                    
                    Format your response EXACTLY as follows:
                    
                    **Chinese characters** • pinyin
                    Context or usage description
                    Example sentence in Chinese
                    
                    __________
                    
                    **Chinese characters** • pinyin
                    Context or usage description
                    Example sentence in Chinese
                    
                    __________
                    
                    **Chinese characters** • pinyin
                    Context or usage description
                    Example sentence in Chinese
                    
                    IMPORTANT: 
                    - Do NOT use brackets [] around anything
                    - Use a divider line (10 underscores: __________) between each translation
                    - Each translation block should have a blank line, then the divider, then another blank line
                    - Each translation must have exactly 3 lines: characters/pinyin, context, example
                    - Continue for up to 5 translations
                    - Order by COLLOQUIAL frequency - most commonly used in everyday conversation first
                    - Focus on how people actually speak, not textbook translations
                    """
                    
                    let userPrompt = "Provide colloquial Chinese translations for everyday conversation: \"\(trimmedText)\""
                    
                    let payload: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userPrompt]
                        ],
                        "temperature": 0.3,
                        "max_tokens": 800,
                        "stream": true
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw EnglishChineseTranslationError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
                    }
                    
                    // Parse Server-Sent Events stream
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            
                            if jsonStr == "[DONE]" {
                                continuation.finish()
                                break
                            }
                            
                            if let data = jsonStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let first = choices.first,
                               let delta = first["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func translate(_ englishText: String) async throws -> TranslationResult {
        guard isConfigured() else {
            throw EnglishChineseTranslationError.notConfigured
        }
        
        let trimmedText = englishText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw EnglishChineseTranslationError.invalidInput("Empty input text")
        }
        
        // Check memory cache
        let cacheKey = trimmedText.lowercased() as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        // Check disk cache
        if let diskCached = loadFromDiskCache(key: cacheKey as String) {
            cache.setObject(diskCached, forKey: cacheKey)
            return diskCached
        }
        
        // Perform translation
        let result = try await performTranslation(trimmedText)
        
        // Cache the result
        cache.setObject(result, forKey: cacheKey)
        saveToDiskCache(result, key: cacheKey as String)
        
        return result
    }
    
    private func performTranslation(_ text: String) async throws -> TranslationResult {
        guard let key = configService.openAIKey,
              let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw EnglishChineseTranslationError.invalidConfiguration
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are a professional English-to-Chinese translator. For the given English word or phrase, provide the most common Chinese translations with their contexts.
        
        Return a JSON array with up to 5 most common translations. Each translation should include:
        - chinese: The Chinese translation (simplified characters)
        - pinyin: The pinyin with tone marks
        - context: Specific context or domain where this translation is used (e.g., "business", "casual conversation", "technical", "literary", "medical")
        - usage: A brief example sentence in Chinese showing how it's used
        - formality: "formal", "informal", or "neutral"
        
        Focus on practical, commonly used translations. Order by frequency of use.
        
        Example response format:
        [
          {
            "chinese": "你好",
            "pinyin": "nǐ hǎo",
            "context": "general greeting",
            "usage": "你好，很高兴认识你",
            "formality": "neutral"
          }
        ]
        """
        
        let userPrompt = "Translate to Chinese with contexts: \"\(text)\""
        
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.3,
            "max_tokens": 800,
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EnglishChineseTranslationError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw EnglishChineseTranslationError.invalidResponse
        }
        
        // Parse the JSON response
        let contentData = content.data(using: .utf8)!
        guard let translationsJson = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let translationsArray = translationsJson["translations"] as? [[String: Any]] ?? translationsJson["results"] as? [[String: Any]] else {
            // Try parsing as direct array
            let contentData = content.data(using: .utf8)!
            guard let directArray = try? JSONSerialization.jsonObject(with: contentData) as? [[String: Any]] else {
                throw EnglishChineseTranslationError.invalidResponse
            }
            return try parseTranslations(from: directArray, query: text)
        }
        
        return try parseTranslations(from: translationsArray, query: text)
    }
    
    private func parseTranslations(from array: [[String: Any]], query: String) throws -> TranslationResult {
        let translations = array.compactMap { dict -> ChineseTranslation? in
            guard let chinese = dict["chinese"] as? String,
                  let pinyin = dict["pinyin"] as? String,
                  let context = dict["context"] as? String,
                  let usage = dict["usage"] as? String,
                  let formality = dict["formality"] as? String else {
                return nil
            }
            
            return ChineseTranslation(
                chinese: chinese,
                pinyin: pinyin,
                context: context,
                usage: usage,
                formality: formality
            )
        }
        
        guard !translations.isEmpty else {
            throw EnglishChineseTranslationError.noTranslationsFound
        }
        
        return TranslationResult(
            query: query,
            translations: translations,
            timestamp: Date()
        )
    }
    
    // MARK: - Disk Cache Management
    private func loadDiskCache() {
        guard let diskCache = diskCache else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCache, includingPropertiesForKeys: [.creationDateKey])
            let now = Date()
            
            for file in files {
                // Check age
                if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   now.timeIntervalSince(creationDate) > maxCacheAge {
                    // Delete old cache
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                
                // Load into memory cache
                if let data = try? Data(contentsOf: file),
                   let result = try? JSONDecoder().decode(TranslationResult.self, from: data) {
                    let key = file.deletingPathExtension().lastPathComponent as NSString
                    cache.setObject(result, forKey: key)
                }
            }
        } catch {
            print("Failed to load disk cache: \(error)")
        }
    }
    
    private func loadFromDiskCache(key: String) -> TranslationResult? {
        guard let diskCache = diskCache else { return nil }
        
        let fileURL = diskCache.appendingPathComponent("\(key.sha256()).json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let result = try? JSONDecoder().decode(TranslationResult.self, from: data) else {
            return nil
        }
        
        // Check age
        if Date().timeIntervalSince(result.timestamp) > maxCacheAge {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        
        return result
    }
    
    private func saveToDiskCache(_ result: TranslationResult, key: String) {
        guard let diskCache = diskCache else { return }
        
        let fileURL = diskCache.appendingPathComponent("\(key.sha256()).json")
        
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: fileURL)
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        
        if let diskCache = diskCache {
            try? FileManager.default.removeItem(at: diskCache)
            try? FileManager.default.createDirectory(at: diskCache, withIntermediateDirectories: true)
        }
    }
}

// MARK: - Error Types
enum EnglishChineseTranslationError: LocalizedError {
    case notConfigured
    case invalidConfiguration
    case invalidInput(String)
    case httpError(Int)
    case invalidResponse
    case noTranslationsFound
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenAI API key not configured"
        case .invalidConfiguration:
            return "Invalid API configuration"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .invalidResponse:
            return "Invalid response from API"
        case .noTranslationsFound:
            return "No translations found"
        }
    }
}

// String extension sha256() is already defined in TranslationServiceOpenAI.swift