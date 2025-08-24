import Foundation
import os.log

struct ProcessedSentence {
    let chinese: String
    let pinyin: [String]
    let english: String
}

class ChineseProcessingService {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "ChineseProcessing")
    private let configService: ConfigService
    
    init(configService: ConfigService) {
        self.configService = configService
    }
    
    func processBatch(_ texts: [String], script: ChineseScript) async throws -> [ProcessedSentence] {
        guard !texts.isEmpty else { return [] }
        
        guard let apiKey = configService.openAIKey else {
            throw ChineseProcessingError.noAPIKey
        }
        
        logger.info("Processing batch of \(texts.count) texts")
        
        let scriptDescription = script == .simplified ? "Simplified Chinese" : "Traditional Chinese"
        
        // Create a numbered list for the prompt
        let numberedTexts = texts.enumerated().map { index, text in
            "\(index + 1). \(text)"
        }.joined(separator: "\n")
        
        let payload: [String: Any] = [
            "model": configService.translationModel,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are a Chinese language expert. For each line of \(scriptDescription) text provided, generate:
                    1. Pinyin with tone marks (one syllable per character, separated by spaces)
                    2. English translation
                    
                    Return a JSON array where each element corresponds to the input line number, in this exact format:
                    [
                        {
                            "pinyin": "syllable1 syllable2 syllable3",
                            "english": "English translation here"
                        },
                        ...
                    ]
                    
                    Process ALL lines and maintain the same order. No markdown, no commentary. JUST the JSON.
                    """
                ],
                [
                    "role": "user",
                    "content": numberedTexts
                ]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            logger.error("API request failed")
            throw ChineseProcessingError.apiError
        }
        
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = result?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChineseProcessingError.invalidResponse
        }
        
        logger.debug("Raw response: \(content)")
        
        // Parse the JSON array response
        guard let jsonData = content.data(using: .utf8),
              let parsedArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]] else {
            logger.error("Failed to parse response array")
            throw ChineseProcessingError.invalidResponse
        }
        
        // Convert parsed data to ProcessedSentence objects
        var results: [ProcessedSentence] = []
        for (index, text) in texts.enumerated() {
            if index < parsedArray.count,
               let pinyinString = parsedArray[index]["pinyin"],
               let english = parsedArray[index]["english"] {
                
                let pinyinArray = pinyinString.components(separatedBy: " ").filter { !$0.isEmpty }
                results.append(ProcessedSentence(
                    chinese: text,
                    pinyin: pinyinArray,
                    english: english
                ))
            } else {
                // Fallback if response is incomplete
                results.append(ProcessedSentence(
                    chinese: text,
                    pinyin: [],
                    english: ""
                ))
            }
        }
        
        logger.info("Processed \(results.count) sentences")
        return results
    }
    
    func processChinese(_ text: String, script: ChineseScript) async throws -> ProcessedSentence {
        guard let apiKey = configService.openAIKey else {
            throw ChineseProcessingError.noAPIKey
        }
        
        logger.info("Processing text: \(text)")
        
        let scriptDescription = script == .simplified ? "Simplified Chinese" : "Traditional Chinese"
        
        let payload: [String: Any] = [
            "model": configService.translationModel,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are a Chinese language expert. For the given \(scriptDescription) text, provide:
                    1. Pinyin with tone marks (one syllable per character, separated by spaces)
                    2. English translation
                    
                    Return ONLY a JSON object in this exact format:
                    {
                        "pinyin": "syllable1 syllable2 syllable3",
                        "english": "English translation here"
                    }
                    """
                ],
                [
                    "role": "user",
                    "content": text
                ]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            logger.error("API request failed")
            throw ChineseProcessingError.apiError
        }
        
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = result?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChineseProcessingError.invalidResponse
        }
        
        logger.debug("Raw response: \(content)")
        
        // Parse the JSON response
        guard let jsonData = content.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
              let pinyinString = parsed["pinyin"],
              let english = parsed["english"] else {
            logger.error("Failed to parse response")
            throw ChineseProcessingError.invalidResponse
        }
        
        let pinyinArray = pinyinString.components(separatedBy: " ").filter { !$0.isEmpty }
        
        logger.debug("Parsed - Pinyin: \(pinyinArray), English: \(english)")
        
        return ProcessedSentence(
            chinese: text,
            pinyin: pinyinArray,
            english: english
        )
    }
}

enum ChineseProcessingError: Error {
    case noAPIKey
    case apiError
    case invalidResponse
}
