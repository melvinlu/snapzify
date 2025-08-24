import Foundation
import os.log

class PinyinServiceOpenAI: PinyinService {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "PinyinService")
    private let configService: ConfigService
    
    init(configService: ConfigService) {
        self.configService = configService
    }
    
    func getPinyin(for text: String, script: ChineseScript) async -> [String] {
        do {
            return try await getPinyinWithAI(text, script: script)
        } catch {
            logger.error("Failed to get pinyin with AI, falling back to empty: \(error.localizedDescription)")
            return Array(repeating: "", count: text.count)
        }
    }
    
    func getPinyinForTokens(_ tokens: [Token], script: ChineseScript) async -> [String] {
        let fullText = tokens.map { $0.text }.joined()
        return await getPinyin(for: fullText, script: script)
    }
    
    private func getPinyinWithAI(_ text: String, script: ChineseScript) async throws -> [String] {
        guard let apiKey = configService.openAIKey else {
            throw PinyinError.noAPIKey
        }
        
        logger.info("Generating pinyin for text: \(text)")
        
        let scriptDescription = script == .simplified ? "Simplified Chinese" : "Traditional Chinese"
        
        let payload: [String: Any] = [
            "model": configService.translationModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a Chinese language expert. For the given \(scriptDescription) text, return ONLY the pinyin with tone marks, separated by spaces. One pinyin syllable per Chinese character. Use tone marks (ā, á, ǎ, à, etc.). Do not include JSON formatting, brackets, or quotes - just the pinyin syllables separated by spaces."
                ],
                [
                    "role": "user",
                    "content": "\(text)"
                ]
            ],
            "temperature": 0.1,
            "max_tokens": 1000
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PinyinError.apiError
        }
        
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = result?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PinyinError.invalidResponse
        }
        
        logger.debug("Raw response content: \(content)")
        
        // Clean up the content
        let cleanedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First try to parse as simple space-separated pinyin (preferred format)
        if !cleanedContent.contains("[") && !cleanedContent.contains("{") {
            let pinyinSyllables = cleanedContent.components(separatedBy: CharacterSet.whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            if !pinyinSyllables.isEmpty {
                logger.debug("Parsed pinyin syllables: \(pinyinSyllables)")
                return pinyinSyllables
            }
        }
        
        // Fallback: try to parse as JSON if the response is still in JSON format
        if cleanedContent.hasPrefix("[") {
            if let jsonData = cleanedContent.data(using: .utf8),
               let pinyinArray = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
                logger.debug("Parsed from JSON: \(pinyinArray)")
                return pinyinArray
            }
        }
        
        // Final fallback
        logger.warning("Failed to parse pinyin, returning empty array")
        return Array(repeating: "", count: text.count)
    }
}

enum PinyinError: Error {
    case noAPIKey
    case apiError
    case invalidResponse
}