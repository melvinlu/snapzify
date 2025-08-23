import Foundation
import UIKit

class OCRServiceOpenAI: OCRService {
    private let configService: ConfigService
    
    init(configService: ConfigService) {
        self.configService = configService
    }
    
    func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        guard let apiKey = configService.openAIKey else {
            throw OCRError.noAPIKey
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw OCRError.invalidImage
        }
        
        let base64Image = imageData.base64EncodedString()
        
        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Extract all text from this image. Return the text as a JSON array of objects, where each object has 'text' (the extracted text) and 'bbox' (bounding box with x, y, width, height as normalized coordinates 0-1). Focus on preserving the original order and structure of the text."
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 4000
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OCRError.apiError
        }
        
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = result?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OCRError.invalidResponse
        }
        
        // Try to parse as JSON first
        if let jsonData = content.data(using: .utf8),
           let textBlocks = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            return textBlocks.compactMap { block in
                guard let text = block["text"] as? String,
                      let bboxDict = block["bbox"] as? [String: Double] else {
                    return nil
                }
                
                let bbox = CGRect(
                    x: (bboxDict["x"] ?? 0) * image.size.width,
                    y: (bboxDict["y"] ?? 0) * image.size.height,
                    width: (bboxDict["width"] ?? 1) * image.size.width,
                    height: (bboxDict["height"] ?? 0.1) * image.size.height
                )
                
                return OCRLine(text: text, bbox: bbox, words: [])
            }
        }
        
        // Fallback: treat the entire response as one text block
        let fallbackBox = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        return [OCRLine(text: content, bbox: fallbackBox, words: [])]
    }
}

enum OCRError: Error {
    case invalidImage
    case noAPIKey
    case apiError
    case invalidResponse
}