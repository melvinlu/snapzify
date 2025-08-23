import Foundation
import CoreGraphics

class SentenceSegmentationServiceOpenAI: SentenceSegmentationService {
    private let configService: ConfigService
    
    init(configService: ConfigService) {
        self.configService = configService
    }
    
    func segmentIntoSentences(from lines: [OCRLine]) async -> [(text: String, bbox: CGRect)] {
        let fullText = lines.map { $0.text }.joined(separator: " ")
        
        guard !fullText.isEmpty else { return [] }
        
        do {
            let sentences = try await segmentSentencesWithAI(fullText)
            return sentences.enumerated().map { index, sentence in
                // Create a rough bounding box for each sentence based on original lines
                let lineHeight: CGFloat = lines.first?.bbox.height ?? 50
                let yOffset = CGFloat(index) * lineHeight
                let bbox = CGRect(
                    x: lines.first?.bbox.minX ?? 0,
                    y: (lines.first?.bbox.minY ?? 0) + yOffset,
                    width: lines.first?.bbox.width ?? 300,
                    height: lineHeight
                )
                return (text: sentence, bbox: bbox)
            }
        } catch {
            print("Failed to segment with AI, falling back to local segmentation: \(error)")
            return segmentLocally(from: lines)
        }
    }
    
    private func segmentSentencesWithAI(_ text: String) async throws -> [String] {
        guard let apiKey = configService.openAIKey else {
            throw SegmentationError.noAPIKey
        }
        
        let payload: [String: Any] = [
            "model": configService.translationModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a Chinese text segmentation expert. Segment the given text into individual sentences. Return only a JSON array of strings, with each string being a complete sentence. Preserve the original Chinese characters exactly as they appear."
                ],
                [
                    "role": "user",
                    "content": "Segment this text into sentences: \(text)"
                ]
            ],
            "temperature": 0.1,
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
            throw SegmentationError.apiError
        }
        
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = result?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SegmentationError.invalidResponse
        }
        
        // Parse the JSON response
        if let jsonData = content.data(using: .utf8),
           let sentences = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            return sentences.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        // Fallback: split by common sentence endings
        return text.components(separatedBy: CharacterSet(charactersIn: "。！？"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    
    private func segmentLocally(from lines: [OCRLine]) -> [(text: String, bbox: CGRect)] {
        var sentences: [(text: String, bbox: CGRect)] = []
        var currentSentence = ""
        var currentBoxes: [CGRect] = []
        
        let sentenceEnders = CharacterSet(charactersIn: "。！？；：…")
        let quotationMarks = CharacterSet(charactersIn: "」』\"》）】")
        
        for line in lines {
            let text = line.text
            var buffer = ""
            
            for (index, char) in text.enumerated() {
                buffer.append(char)
                
                if sentenceEnders.contains(char.unicodeScalars.first!) {
                    if index < text.count - 1 {
                        let nextChar = text[text.index(text.startIndex, offsetBy: index + 1)]
                        if quotationMarks.contains(nextChar.unicodeScalars.first!) {
                            continue
                        }
                    }
                    
                    currentSentence += buffer
                    currentBoxes.append(line.bbox)
                    
                    if !currentSentence.isEmpty {
                        let unionBox = currentBoxes.reduce(CGRect.null) { $0.union($1) }
                        sentences.append((text: currentSentence, bbox: unionBox))
                        currentSentence = ""
                        currentBoxes = []
                    }
                    buffer = ""
                }
            }
            
            if !buffer.isEmpty {
                currentSentence += buffer
                currentBoxes.append(line.bbox)
            }
        }
        
        if !currentSentence.isEmpty {
            let unionBox = currentBoxes.reduce(CGRect.null) { $0.union($1) }
            sentences.append((text: currentSentence, bbox: unionBox))
        }
        
        return sentences
    }
    
    func tokenize(_ sentence: String) async -> [Token] {
        do {
            return try await tokenizeWithAI(sentence)
        } catch {
            print("Failed to tokenize with AI, falling back to character splitting: \(error)")
            return sentence.map { Token(text: String($0)) }
        }
    }
    
    private func tokenizeWithAI(_ sentence: String) async throws -> [Token] {
        guard let apiKey = configService.openAIKey else {
            throw SegmentationError.noAPIKey
        }
        
        let payload: [String: Any] = [
            "model": configService.translationModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a Chinese text tokenization expert. Break the given Chinese sentence into meaningful word tokens. Return only a JSON array of strings, where each string is a single word or meaningful unit."
                ],
                [
                    "role": "user",
                    "content": "Tokenize this Chinese sentence: \(sentence)"
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
            throw SegmentationError.apiError
        }
        
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = result?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SegmentationError.invalidResponse
        }
        
        // Parse the JSON response
        if let jsonData = content.data(using: .utf8),
           let tokens = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            return tokens.map { Token(text: $0) }
        }
        
        // Fallback
        return sentence.map { Token(text: String($0)) }
    }
}

enum SegmentationError: Error {
    case noAPIKey
    case apiError
    case invalidResponse
}