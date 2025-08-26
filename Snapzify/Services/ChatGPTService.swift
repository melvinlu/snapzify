import Foundation

protocol ChatGPTService {
    func streamBreakdown(chineseText: String) -> AsyncThrowingStream<String, Error>
    func streamCustomPrompt(chineseText: String, userPrompt: String) -> AsyncThrowingStream<String, Error>
    func isConfigured() -> Bool
}

class ChatGPTServiceImpl: ChatGPTService {
    private let configService: ConfigService
    
    init(configService: ConfigService) {
        self.configService = configService
    }
    
    func isConfigured() -> Bool {
        guard let key = configService.openAIKey,
              !key.isEmpty,
              key != "REPLACE_WITH_YOUR_OPENAI_KEY" else {
            return false
        }
        return true
    }
    
    func streamBreakdown(chineseText: String) -> AsyncThrowingStream<String, Error> {
        let prompt = "Breakdown: \(chineseText)"
        return streamChatGPT(prompt: prompt)
    }
    
    func streamCustomPrompt(chineseText: String, userPrompt: String) -> AsyncThrowingStream<String, Error> {
        let combinedPrompt = "\(chineseText) \(userPrompt)"
        return streamChatGPT(prompt: combinedPrompt)
    }
    
    private func streamChatGPT(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let key = configService.openAIKey,
                          let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
                        throw TranslationError.invalidConfiguration
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let payload: [String: Any] = [
                        "model": "gpt-4o-mini",
                        "messages": [
                            ["role": "system", "content": "You are a helpful Chinese language tutor. Provide clear, concise explanations of Chinese text, breaking down meanings, grammar, and cultural context as needed."],
                            ["role": "user", "content": prompt]
                        ],
                        "temperature": 0.7,
                        "max_tokens": 500,
                        "stream": true
                    ]
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw TranslationError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
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
}