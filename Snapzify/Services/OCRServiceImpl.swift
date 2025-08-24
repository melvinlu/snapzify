import Foundation
import UIKit
import os.log

class OCRServiceImpl: OCRService {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "OCR")
    private let googleCloudVisionURL = "https://vision.googleapis.com/v1/images:annotate"
    private let configService = ConfigServiceImpl()
    
    func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        logger.info("Starting text recognition with Google Cloud Vision")
        
        // Get API key from config
        guard let apiKey = configService.googleCloudVisionKey, !apiKey.isEmpty else {
            logger.error("No Google Cloud Vision API key configured")
            throw OCRError.noAPIKey
        }
        
        // Resize image if too large
        let resizedImage = resizeImageIfNeeded(image)
        
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            logger.error("Failed to convert image to JPEG")
            throw OCRError.invalidImage
        }
        
        logger.debug("Image converted to JPEG, size: \(imageData.count) bytes")
        
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
        
        logger.debug("Creating Google Cloud Vision API request")
        
        // Use API key authentication
        let urlWithKey = "\(googleCloudVisionURL)?key=\(apiKey)"
        var request = URLRequest(url: URL(string: urlWithKey)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 30.0
        
        logger.info("Sending request to Google Cloud Vision")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type")
            throw OCRError.apiError
        }
        
        logger.debug("Response status code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            logger.error("API request failed with status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.error("Error response: \(responseString)")
            }
            throw OCRError.apiError
        }
        
        // Parse the response
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responses = result?["responses"] as? [[String: Any]],
              let firstResponse = responses.first else {
            logger.error("Failed to parse Google Cloud Vision response")
            throw OCRError.invalidResponse
        }
        
        var ocrLines: [OCRLine] = []
        
        // Try to get full text annotation first (better for documents)
        if let fullTextAnnotation = firstResponse["fullTextAnnotation"] as? [String: Any],
           let pages = fullTextAnnotation["pages"] as? [[String: Any]] {
            
            logger.debug("Processing full text annotation")
            
            for page in pages {
                if let blocks = page["blocks"] as? [[String: Any]] {
                    for block in blocks {
                        if let paragraphs = block["paragraphs"] as? [[String: Any]] {
                            for paragraph in paragraphs {
                                var currentLineText = ""
                                var lineTexts: [String] = []
                                var paragraphBbox: CGRect?
                                var currentLineMinY: Int?
                                var currentLineMaxY: Int?
                                
                                // Get bounding box for paragraph first
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
                                
                                if let words = paragraph["words"] as? [[String: Any]] {
                                    for word in words {
                                        // Get word bounding box to track vertical position
                                        var wordMinY: Int?
                                        var wordMaxY: Int?
                                        if let wordBbox = word["boundingBox"] as? [String: Any],
                                           let vertices = wordBbox["vertices"] as? [[String: Any]],
                                           vertices.count >= 4 {
                                            wordMinY = vertices.compactMap { ($0["y"] as? Int) ?? 0 }.min()
                                            wordMaxY = vertices.compactMap { ($0["y"] as? Int) ?? 0 }.max()
                                        }
                                        
                                        // Check if this word is on a new line (significant Y position change)
                                        if let currentY = currentLineMinY,
                                           let wordY = wordMinY,
                                           abs(wordY - currentY) > 10 {  // Threshold for detecting new line
                                            // Save current line
                                            let trimmedLine = currentLineText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !trimmedLine.isEmpty {
                                                lineTexts.append(trimmedLine)
                                            }
                                            currentLineText = ""
                                            currentLineMinY = wordMinY
                                            currentLineMaxY = wordMaxY
                                        } else if currentLineMinY == nil {
                                            currentLineMinY = wordMinY
                                            currentLineMaxY = wordMaxY
                                        }
                                        
                                        if let symbols = word["symbols"] as? [[String: Any]] {
                                            for symbol in symbols {
                                                if let text = symbol["text"] as? String {
                                                    currentLineText += text
                                                }
                                                // Check for breaks after symbol
                                                if let property = symbol["property"] as? [String: Any],
                                                   let detectedBreak = property["detectedBreak"] as? [String: Any],
                                                   let breakType = detectedBreak["type"] as? String {
                                                    if breakType == "SPACE" || breakType == "EOL_SURE_SPACE" {
                                                        currentLineText += " "
                                                    } else if breakType == "LINE_BREAK" || breakType == "EOL_SURE_BREAK" {
                                                        // Explicit line break detected
                                                        let trimmedLine = currentLineText.trimmingCharacters(in: .whitespacesAndNewlines)
                                                        if !trimmedLine.isEmpty {
                                                            lineTexts.append(trimmedLine)
                                                        }
                                                        currentLineText = ""
                                                        currentLineMinY = nil
                                                        currentLineMaxY = nil
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Add remaining text as final line
                                let trimmedLine = currentLineText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmedLine.isEmpty {
                                    lineTexts.append(trimmedLine)
                                }
                                
                                // Add each line as a separate OCRLine
                                for lineText in lineTexts {
                                    ocrLines.append(OCRLine(
                                        text: lineText,
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
            logger.debug("Using text annotations fallback")
            
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
        
        logger.info("Successfully extracted \(ocrLines.count) lines of text")
        
        if ocrLines.isEmpty {
            // If no text found, return a message
            return [OCRLine(
                text: "No text detected",
                bbox: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height),
                words: []
            )]
        }
        
        return ocrLines
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
