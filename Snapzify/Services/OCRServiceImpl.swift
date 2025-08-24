import Foundation
import UIKit

class OCRServiceImpl: OCRService {
    private let googleCloudVisionURL = "https://vision.googleapis.com/v1/images:annotate"
    private let configService = ConfigServiceImpl()
    
    func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        print("OCR: Starting text recognition with Google Cloud Vision...")
        
        // Get API key from config
        guard let apiKey = configService.googleCloudVisionKey, !apiKey.isEmpty else {
            print("OCR: No Google Cloud Vision API key configured")
            throw OCRError.noAPIKey
        }
        
        // Resize image if too large
        let resizedImage = resizeImageIfNeeded(image)
        
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            print("OCR: Failed to convert image to JPEG")
            throw OCRError.invalidImage
        }
        
        print("OCR: Image converted to JPEG, size: \(imageData.count) bytes")
        
        let base64Image = imageData.base64EncodedString()
        
        // Create request payload for Google Cloud Vision
        let payload: [String: Any] = [
            "requests": [
                [
                    "image": [
                        "content": base64Image
                    ],
                    "features": [
                        [
                            "type": "TEXT_DETECTION",
                            "maxResults": 50
                        ],
                        [
                            "type": "DOCUMENT_TEXT_DETECTION",
                            "maxResults": 50
                        ]
                    ],
                    "imageContext": [
                        "languageHints": ["zh", "zh-Hans", "zh-Hant", "en"]
                    ]
                ]
            ]
        ]
        
        print("OCR: Creating Google Cloud Vision API request...")
        
        // Use API key authentication
        let urlWithKey = "\(googleCloudVisionURL)?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlWithKey)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30.0
        
        print("OCR: Sending request to Google Cloud Vision...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
        
        // Parse the response
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responses = result?["responses"] as? [[String: Any]],
              let firstResponse = responses.first else {
            print("OCR: Failed to parse Google Cloud Vision response")
            throw OCRError.invalidResponse
        }
        
        var ocrLines: [OCRLine] = []
        
        // Try to get full text annotation first (better for documents)
        if let fullTextAnnotation = firstResponse["fullTextAnnotation"] as? [String: Any],
           let pages = fullTextAnnotation["pages"] as? [[String: Any]] {
            
            print("OCR: Processing full text annotation...")
            
            for page in pages {
                if let blocks = page["blocks"] as? [[String: Any]] {
                    for block in blocks {
                        if let paragraphs = block["paragraphs"] as? [[String: Any]] {
                            for paragraph in paragraphs {
                                var paragraphText = ""
                                var paragraphBbox: CGRect?
                                
                                if let words = paragraph["words"] as? [[String: Any]] {
                                    for word in words {
                                        if let symbols = word["symbols"] as? [[String: Any]] {
                                            for symbol in symbols {
                                                if let text = symbol["text"] as? String {
                                                    paragraphText += text
                                                }
                                                // Check for space after symbol
                                                if let property = symbol["property"] as? [String: Any],
                                                   let detectedBreak = property["detectedBreak"] as? [String: Any],
                                                   let breakType = detectedBreak["type"] as? String {
                                                    if breakType == "SPACE" || breakType == "EOL_SURE_SPACE" {
                                                        paragraphText += " "
                                                    } else if breakType == "LINE_BREAK" || breakType == "EOL_SURE_BREAK" {
                                                        // This is a line break, so we should treat this as end of line
                                                        let trimmedText = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
                                                        if !trimmedText.isEmpty {
                                                            ocrLines.append(OCRLine(
                                                                text: trimmedText,
                                                                bbox: paragraphBbox ?? CGRect(x: 0, y: 0, width: image.size.width, height: 50),
                                                                words: []
                                                            ))
                                                            paragraphText = ""
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Get bounding box for paragraph
                                if let boundingBox = paragraph["boundingBox"] as? [String: Any],
                                   let vertices = boundingBox["vertices"] as? [[String: Any]],
                                   vertices.count >= 4 {
                                    
                                    let minX = vertices.compactMap { ($0["x"] as? Int) ?? 0 }.min() ?? 0
                                    let minY = vertices.compactMap { ($0["y"] as? Int) ?? 0 }.min() ?? 0
                                    let maxX = vertices.compactMap { ($0["x"] as? Int) ?? 0 }.max() ?? 0
                                    let maxY = vertices.compactMap { ($0["y"] as? Int) ?? 0 }.max() ?? 0
                                    
                                    paragraphBbox = CGRect(
                                        x: Double(minX),
                                        y: Double(minY),
                                        width: Double(maxX - minX),
                                        height: Double(maxY - minY)
                                    )
                                }
                                
                                // Add remaining text if any
                                let trimmedText = paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmedText.isEmpty {
                                    ocrLines.append(OCRLine(
                                        text: trimmedText,
                                        bbox: paragraphBbox ?? CGRect(x: 0, y: 0, width: image.size.width, height: 50),
                                        words: []
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        } else if let textAnnotations = firstResponse["textAnnotations"] as? [[String: Any]] {
            // Fallback to text annotations
            print("OCR: Using text annotations fallback...")
            
            // The first annotation contains all text, split it by lines
            if let firstAnnotation = textAnnotations.first,
               let fullText = firstAnnotation["description"] as? String {
                
                let lines = fullText.components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedLine.isEmpty {
                        // Create a simple bounding box for each line
                        let lineHeight = image.size.height / CGFloat(lines.count)
                        let bbox = CGRect(
                            x: 0,
                            y: CGFloat(index) * lineHeight,
                            width: image.size.width,
                            height: lineHeight
                        )
                        ocrLines.append(OCRLine(text: trimmedLine, bbox: bbox, words: []))
                    }
                }
            }
        }
        
        print("OCR: Successfully extracted \(ocrLines.count) lines of text")
        
        if ocrLines.isEmpty {
            // If no text found, return a message
            return [OCRLine(
                text: "No text detected",
                bbox: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
                words: []
            )]
        }
        
        // Filter out any lines that don't contain Chinese characters if needed
        let chineseLines = ocrLines.filter { line in
            containsChinese(line.text) || line.text.contains("No text detected")
        }
        
        return chineseLines.isEmpty ? ocrLines : chineseLines
    }
    
    private func containsChinese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for CJK Unified Ideographs ranges
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) ||
               (0x2A700...0x2B73F).contains(scalar.value) ||
               (0x2B740...0x2B81F).contains(scalar.value) ||
               (0x2B820...0x2CEAF).contains(scalar.value) ||
               (0x2CEB0...0x2EBEF).contains(scalar.value) ||
               (0x30000...0x3134F).contains(scalar.value) {
                return true
            }
        }
        return false
    }
    
    private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1024
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