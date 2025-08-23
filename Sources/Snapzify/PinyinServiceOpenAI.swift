import Foundation

class PinyinServiceOpenAI: PinyinService {
    private let configService: ConfigService
    
    init(configService: ConfigService) {
        self.configService = configService
    }
    
    func getPinyin(for text: String, script: ChineseScript) async -> [String] {
        do {
            return try await getPinyinWithAI(text, script: script)
        } catch {
            print("Failed to get pinyin with AI, falling back to empty: \(error)")
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
        
        let scriptDescription = script == .simplified ? "Simplified Chinese" : "Traditional Chinese"
        
        let payload: [String: Any] = [
            "model": configService.translationModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a Chinese language expert. Generate pinyin with tone marks for the given \(scriptDescription) text. Return only a JSON array of strings, where each string is the pinyin for the corresponding character in the input text. Use pinyin with tone marks (ā, á, ǎ, à, etc.). For non-Chinese characters, return empty strings."
                ],
                [
                    "role": "user",
                    "content": "Generate pinyin for: \(text)"
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
        
        // Parse the JSON response
        if let jsonData = content.data(using: .utf8),
           let pinyinArray = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            return pinyinArray
        }
        
        // Fallback: try to extract pinyin from plain text response
        let words = content.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if !words.isEmpty {
            return words
        }
        
        // Final fallback
        return Array(repeating: "", count: text.count)
    }
}

enum PinyinError: Error {
    case noAPIKey
    case apiError
    case invalidResponse
}