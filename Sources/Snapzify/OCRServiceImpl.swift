import Foundation
import UIKit

struct ParsedSentence: Codable {
    let chinese: String
    let pinyin: String
    let english: String
}

class OCRServiceImpl: OCRService {
    private let configService = ConfigServiceImpl()
    
    func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        print("OCR: Starting text recognition...")
        
        guard let apiKey = configService.openAIKey else {
            print("OCR: No API key found")
            throw OCRError.noAPIKey
        }
        
        print("OCR: API key found, processing image...")
        
        // Quick API key validation with a simple text completion first
        print("OCR: Testing API key with simple request...")
        do {
            let testPayload: [String: Any] = [
                "model": "gpt-3.5-turbo",
                "messages": [["role": "user", "content": "test"]],
                "max_tokens": 5
            ]
            var testRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            testRequest.httpMethod = "POST"
            testRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            testRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            testRequest.httpBody = try JSONSerialization.data(withJSONObject: testPayload)
            testRequest.timeoutInterval = 10.0
            
            let (_, testResponse) = try await URLSession.shared.data(for: testRequest)
            if let httpResponse = testResponse as? HTTPURLResponse {
                print("OCR: API key test - HTTP \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    print("OCR: API key appears invalid, status: \(httpResponse.statusCode)")
                    throw OCRError.apiError
                }
            }
            print("OCR: API key validated successfully")
        } catch {
            print("OCR: API key validation failed: \(error)")
            throw OCRError.apiError
        }
        
        // Resize image if too large
        let resizedImage = resizeImageIfNeeded(image)
        
        var finalImageData: Data
        
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.5) else { // Reduced from 0.8 to 0.5
            print("OCR: Failed to convert image to JPEG")
            throw OCRError.invalidImage
        }
        
        print("OCR: Image converted to JPEG, size: \(imageData.count) bytes")
        
        // Check if image data is too large (OpenAI has a 20MB limit)
        if imageData.count > 20 * 1024 * 1024 {
            print("OCR: Image too large (\(imageData.count) bytes), reducing quality")
            guard let smallerData = resizedImage.jpegData(compressionQuality: 0.3) else {
                throw OCRError.invalidImage
            }
            finalImageData = smallerData
            print("OCR: Using compressed image, size: \(finalImageData.count) bytes")
        } else {
            finalImageData = imageData
        }
        
        let base64Image = finalImageData.base64EncodedString()
        print("OCR: Image encoded to base64, length: \(base64Image.count)")
        
        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "From this picture, parse out the Chinese sections (grouped by digital spacing), and also provide pinyin and English for them. For social media screenshots, separate individual comments. Return ONLY a JSON array with this exact format: [{\"chinese\": \"Chinese text\", \"pinyin\": \"pinyin text\", \"english\": \"English translation\"}]. No markdown, no explanations, just the JSON array."
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
            "max_tokens": 3000
        ]
        
        print("OCR: Creating API request...")
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60.0 // 60 second timeout
        
        print("OCR: Sending request to OpenAI...")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            print("OCR: Received response from OpenAI")
        } catch {
            print("OCR: Network request failed: \(error)")
            if let urlError = error as? URLError {
                print("OCR: URLError code: \(urlError.code.rawValue)")
                print("OCR: URLError description: \(urlError.localizedDescription)")
            }
            throw OCRError.apiError
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("OCR: Invalid response type")
            throw OCRError.apiError
        }
        
        print("OCR: Response status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("OCR: API request failed with status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("OCR: Error response: \(responseString)")
            }
            throw OCRError.apiError
        }
        
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = result?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            print("OCR: Failed to parse OpenAI response structure")
            if let responseString = String(data: data, encoding: .utf8) {
                print("OCR: Raw response: \(responseString.prefix(500))...")
            }
            throw OCRError.invalidResponse
        }
        
        print("OCR: Successfully extracted content from OpenAI response")
        print("OCR: Content preview: \(content.prefix(200))...")
        
        // Check for content policy violations
        if content.lowercased().contains("sorry") && content.lowercased().contains("can't assist") {
            print("OCR: Content policy violation detected, content may be inappropriate for OpenAI")
            throw OCRError.apiError
        }
        
        // Try to parse as JSON array of parsed sentences
        // First, try to extract JSON from the content (ChatGPT often wraps JSON in markdown)
        let cleanedContent = extractJSONFromContent(content)
        print("OCR: Attempting to parse JSON from cleaned content: \(cleanedContent.prefix(200))...")
        
        if let jsonData = cleanedContent.data(using: .utf8) {
            do {
                let parsedSentences = try JSONDecoder().decode([ParsedSentence].self, from: jsonData)
                print("OCR: Successfully parsed \(parsedSentences.count) sentences from JSON response")
                
                // Convert parsed sentences to OCRLine format
                return parsedSentences.enumerated().map { index, parsed in
                    let lineHeight = image.size.height / CGFloat(parsedSentences.count)
                    let bbox = CGRect(
                        x: 0,
                        y: CGFloat(index) * lineHeight,
                        width: image.size.width,
                        height: lineHeight
                    )
                    // Store complete parsed data in the text field temporarily 
                    // We'll extract it later in the processing pipeline
                    let combinedText = "\(parsed.chinese)|\(parsed.pinyin)|\(parsed.english)"
                    return OCRLine(text: combinedText, bbox: bbox, words: [])
                }
            } catch {
                print("OCR: Failed to parse JSON response: \(error)")
                print("OCR: JSON content: \(cleanedContent.prefix(500))")
                // Fall back to treating as plain text
            }
        }
        
        // Fallback: split content into lines for basic processing
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        print("OCR: Using fallback text parsing, split content into \(lines.count) lines")
        
        if lines.isEmpty {
            // If no lines, return the original content as one block
            let fallbackBox = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
            return [OCRLine(text: content, bbox: fallbackBox, words: [])]
        }
        
        // Create OCR lines with estimated bounding boxes
        return lines.enumerated().map { index, lineText in
            let lineHeight = image.size.height / CGFloat(lines.count)
            let bbox = CGRect(
                x: 0,
                y: CGFloat(index) * lineHeight,
                width: image.size.width,
                height: lineHeight
            )
            return OCRLine(text: lineText, bbox: bbox, words: [])
        }
    }
    
    private func extractJSONFromContent(_ content: String) -> String {
        // ChatGPT often wraps JSON in markdown code blocks
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Look for JSON array patterns
        if let startRange = trimmedContent.range(of: "["),
           let endRange = trimmedContent.range(of: "]", options: .backwards) {
            let jsonContent = String(trimmedContent[startRange.lowerBound...endRange.upperBound])
            return jsonContent
        }
        
        // Look for markdown code blocks
        if trimmedContent.hasPrefix("```") {
            let lines = trimmedContent.components(separatedBy: .newlines)
            var jsonLines: [String] = []
            var inCodeBlock = false
            
            for line in lines {
                if line.hasPrefix("```") {
                    if inCodeBlock {
                        break // End of code block
                    } else {
                        inCodeBlock = true // Start of code block
                        continue
                    }
                }
                if inCodeBlock {
                    jsonLines.append(line)
                }
            }
            
            return jsonLines.joined(separator: "\n")
        }
        
        // Return as-is if no special formatting detected
        return trimmedContent
    }
    
    private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024 // Reduced from 2048 to 1024 for faster processing
        let currentMax = max(image.size.width, image.size.height)
        
        if currentMax <= maxDimension {
            return image
        }
        
        let scale = maxDimension / currentMax
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? image
    }
}

enum OCRError: Error {
    case invalidImage
    case noAPIKey
    case apiError
    case invalidResponse
}
