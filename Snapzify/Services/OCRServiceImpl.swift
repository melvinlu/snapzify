import Foundation
import UIKit
import os.log

// Helper structures for better OCR token handling
struct OCRToken {
    let text: String
    let minX: CGFloat
    let maxX: CGFloat
    let minY: CGFloat
    let maxY: CGFloat
}

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
                                var paragraphBbox: CGRect?
                                
                                // Get bounding box for paragraph
                                if let boundingBox = paragraph["boundingBox"] as? [String: Any],
                                   let bbox = bboxFrom(boundingBox) {
                                    paragraphBbox = CGRect(
                                        x: bbox.minX,
                                        y: bbox.minY,
                                        width: bbox.maxX - bbox.minX,
                                        height: bbox.maxY - bbox.minY
                                    )
                                }
                                
                                // Collect tokens from this paragraph
                                var tokens: [OCRToken] = []
                                
                                if let words = paragraph["words"] as? [[String: Any]] {
                                    for word in words {
                                        guard let wordBox = word["boundingBox"] as? [String: Any],
                                              let bb = bboxFrom(wordBox) else { continue }
                                        
                                        var buffer = ""
                                        if let symbols = word["symbols"] as? [[String: Any]] {
                                            for sym in symbols {
                                                if let t = sym["text"] as? String { 
                                                    buffer += t 
                                                }
                                                // Check symbol-level breaks
                                                if let prop = sym["property"] as? [String: Any],
                                                   let db = prop["detectedBreak"] as? [String: Any],
                                                   let type = db["type"] as? String {
                                                    if type == "SPACE" || type == "EOL_SURE_SPACE" { 
                                                        buffer += " " 
                                                    }
                                                    if type == "LINE_BREAK" || type == "EOL_SURE_BREAK" { 
                                                        buffer += "\n" 
                                                    }
                                                }
                                            }
                                        }
                                        
                                        // Also check word-level breaks
                                        if let prop = word["property"] as? [String: Any],
                                           let db = prop["detectedBreak"] as? [String: Any],
                                           let type = db["type"] as? String {
                                            if type == "SPACE" || type == "EOL_SURE_SPACE" { 
                                                buffer += " " 
                                            }
                                            if type == "LINE_BREAK" || type == "EOL_SURE_BREAK" { 
                                                buffer += "\n" 
                                            }
                                        }
                                        
                                        if !buffer.isEmpty {
                                            tokens.append(OCRToken(
                                                text: buffer,
                                                minX: bb.minX,
                                                maxX: bb.maxX,
                                                minY: bb.minY,
                                                maxY: bb.maxY
                                            ))
                                        }
                                    }
                                }
                                
                                // Group tokens into lines by Y overlap
                                tokens.sort { ($0.minY + $0.maxY)/2 < ($1.minY + $1.maxY)/2 }
                                
                                var linesTokens: [[OCRToken]] = []
                                for tok in tokens {
                                    if var lastLine = linesTokens.last {
                                        // Compare vertical overlap with last line's vertical span
                                        let lMinY = lastLine.map(\.minY).min()!
                                        let lMaxY = lastLine.map(\.maxY).max()!
                                        let ov = overlapRatio(lMinY, lMaxY, tok.minY, tok.maxY)
                                        if ov >= 0.35 { // Same line if 35% vertical overlap
                                            lastLine.append(tok)
                                            linesTokens[linesTokens.count - 1] = lastLine
                                        } else {
                                            linesTokens.append([tok])
                                        }
                                    } else {
                                        linesTokens.append([tok])
                                    }
                                }
                                
                                // Process each line: sort by X and split by gaps/punctuation
                                let gapMultiplier: CGFloat = 1.5 // Threshold for "digital space"
                                
                                for line in linesTokens {
                                    let sorted = line.sorted { $0.minX < $1.minX }
                                    
                                    // Estimate average character width on this line
                                    let avgWidth: CGFloat = {
                                        let widths = sorted.map { $0.maxX - $0.minX }
                                        return max(1, widths.reduce(0, +) / CGFloat(max(1, widths.count)))
                                    }()
                                    
                                    var segment = ""
                                    var prev: OCRToken? = nil
                                    
                                    func flush() {
                                        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            ocrLines.append(OCRLine(
                                                text: trimmed,
                                                bbox: paragraphBbox ?? CGRect(x: 0, y: 0, width: image.size.width, height: 50),
                                                words: []
                                            ))
                                        }
                                        segment = ""
                                    }
                                    
                                    for t in sorted {
                                        // Check for explicit newlines or Chinese punctuation
                                        if t.text.contains("\n") || t.text.contains("\u{3000}") {
                                            segment += t.text.replacingOccurrences(of: "\n", with: "")
                                                            .replacingOccurrences(of: "\u{3000}", with: " ")
                                            flush()
                                            prev = nil
                                            continue
                                        }
                                        
                                        // Check for Chinese sentence-ending punctuation
                                        if containsChineseSentenceEnding(t.text) {
                                            segment += t.text
                                            flush()
                                            prev = nil
                                            continue
                                        }
                                        
                                        // Check for gap-based splitting
                                        if let p = prev {
                                            let gap = t.minX - p.maxX
                                            if gap > gapMultiplier * avgWidth {
                                                // Big digital gap => new segment
                                                flush()
                                            } else if gap > 0.25 * avgWidth {
                                                // Mild spacing => insert a space (helps CJK + Latin mixes)
                                                segment += " "
                                            }
                                        }
                                        
                                        segment += t.text
                                        prev = t
                                    }
                                    
                                    // Flush any remaining segment
                                    flush()
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
    
    // MARK: - Helper Functions
    
    private func bboxFrom(_ box: [String: Any]) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        // Prefer normalizedVertices if present (0..1 coordinates)
        if let norm = box["normalizedVertices"] as? [[String: Any]], norm.count >= 4 {
            let xs = norm.compactMap { ($0["x"] as? NSNumber)?.doubleValue }.map { CGFloat($0) }
            let ys = norm.compactMap { ($0["y"] as? NSNumber)?.doubleValue }.map { CGFloat($0) }
            guard !xs.isEmpty, !ys.isEmpty else { return nil }
            // Scale normalized coords to image size if needed
            return (xs.min()! * 1000, xs.max()! * 1000, ys.min()! * 1000, ys.max()! * 1000)
        }
        
        // Fall back to regular vertices
        if let verts = box["vertices"] as? [[String: Any]], verts.count >= 4 {
            // Don't coerce nil to 0 - that ruins gap calculations
            let xs = verts.compactMap { $0["x"] as? NSNumber }.map { CGFloat(truncating: $0) }
            let ys = verts.compactMap { $0["y"] as? NSNumber }.map { CGFloat(truncating: $0) }
            guard xs.count == verts.count, ys.count == verts.count else { return nil }
            return (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        }
        return nil
    }
    
    private func overlapRatio(_ aMin: CGFloat, _ aMax: CGFloat, _ bMin: CGFloat, _ bMax: CGFloat) -> CGFloat {
        let inter = max(0, min(aMax, bMax) - max(aMin, bMin))
        let denom = max(aMax - aMin, bMax - bMin)
        return denom > 0 ? inter / denom : 0
    }
    
    private func containsChineseSentenceEnding(_ text: String) -> Bool {
        // Common Chinese sentence endings
        let punctuation = "。！？；：…—】）」》〉〕〗】"
        for char in text {
            if punctuation.contains(char) {
                return true
            }
        }
        return false
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
