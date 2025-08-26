import Foundation
import os.log

struct StreamingProcessedSentence {
    let chinese: String
    let pinyin: [String]
    let english: String
    let index: Int
}

class StreamingChineseProcessingService {
    private let logger = Logger(subsystem: "com.snapzify.app", category: "StreamingChineseProcessing")
    private let configService: ConfigService
    private let maxConcurrentRequests = 4
    private let chunkSize = 2
    
    init(configService: ConfigService) {
        self.configService = configService
    }
    
    func processStreamingBatch(
        _ texts: [String],
        script: ChineseScript,
        onSentenceProcessed: @escaping (StreamingProcessedSentence) -> Void
    ) async throws {
        guard !texts.isEmpty else { return }
        
        guard let apiKey = configService.openAIKey else {
            throw ChineseProcessingError.noAPIKey
        }
        
        logger.info("Starting streaming batch processing of \(texts.count) texts")
        
        // Process all texts in a single request (sequential, not concurrent)
        do {
            try await processAllTextsStreaming(
                texts,
                script: script,
                apiKey: apiKey,
                onSentenceProcessed: onSentenceProcessed
            )
        } catch {
            logger.error("Failed to process texts: \(error.localizedDescription)")
            throw error
        }
        
        logger.info("Completed streaming batch processing")
    }
    
    private func processAllTextsStreaming(
        _ texts: [String],
        script: ChineseScript,
        apiKey: String,
        onSentenceProcessed: @escaping (StreamingProcessedSentence) -> Void
    ) async throws {
        logger.debug("Processing all \(texts.count) texts in single request")
        
        let scriptDescription = script == .simplified ? "Simplified Chinese" : "Traditional Chinese"
        
        let numberedTexts = texts.enumerated().map { index, text in
            "\(index + 1). \(text)"
        }.joined(separator: "\n")
        
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are a Chinese language expert. For each line of \(scriptDescription) text provided, generate:
                    1. Pinyin with tone marks (one syllable per character, separated by spaces)
                    2. English translation
                    
                    Output EXACTLY one JSON object per input line, each on its own line (JSON Lines format).
                    Each line should be a complete, valid JSON object like this:
                    {"pinyin": "pīn yīn", "english": "English translation"}
                    
                    IMPORTANT:
                    - Output one JSON object per line, NOT an array
                    - Each JSON object must be on a single line
                    - Do not include line numbers in the output
                    - Process lines in the exact order provided
                    - Output ONLY the JSON objects, no other text or formatting
                    """
                ],
                [
                    "role": "user",
                    "content": numberedTexts
                ]
            ],
            "temperature": 0,
            "max_tokens": texts.count * 200, // Adjust based on number of texts
            "stream": true
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ChineseProcessingError.apiError
        }
        
        var buffer = ""
        var currentLineIndex = 0
        
        for try await line in bytes.lines {
            // Parse SSE format
            guard line.hasPrefix("data: ") else { 
                continue 
            }
            let jsonString = String(line.dropFirst(6))
            
            if jsonString == "[DONE]" { 
                logger.debug("Stream completed, processed \(currentLineIndex) sentences")
                break 
            }
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            
            buffer += content
            
            // Try to extract complete JSON lines from buffer
            while let newlineRange = buffer.range(of: "\n") {
                let jsonLine = String(buffer[..<newlineRange.lowerBound])
                buffer = String(buffer[newlineRange.upperBound...])
                
                let trimmedLine = jsonLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty {
                    logger.debug("🔍 Attempting to parse JSON line: '\(trimmedLine)'")
                    if let lineData = trimmedLine.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: String],
                       let pinyinString = parsed["pinyin"],
                       let english = parsed["english"],
                       currentLineIndex < texts.count {
                        
                        logger.info("✅ Successfully parsed sentence \(currentLineIndex): pinyin='\(pinyinString)', english='\(english)'")
                        let pinyinArray = pinyinString.components(separatedBy: " ").filter { !$0.isEmpty }
                        
                        let processed = StreamingProcessedSentence(
                            chinese: texts[currentLineIndex],
                            pinyin: pinyinArray,
                            english: english,
                            index: currentLineIndex
                        )
                        
                        // Call callback on main thread
                        await MainActor.run {
                            onSentenceProcessed(processed)
                        }
                        
                        currentLineIndex += 1
                    }
                }
            }
        }
        
        // Process any remaining buffer
        let remainingBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainingBuffer.isEmpty {
            logger.debug("Processing remaining buffer: \(remainingBuffer)")
            
            if let lineData = remainingBuffer.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: String],
               let pinyinString = parsed["pinyin"],
               let english = parsed["english"],
               currentLineIndex < texts.count {
                
                let pinyinArray = pinyinString.components(separatedBy: " ").filter { !$0.isEmpty }
                
                let processed = StreamingProcessedSentence(
                    chinese: texts[currentLineIndex],
                    pinyin: pinyinArray,
                    english: english,
                    index: currentLineIndex
                )
                
                await MainActor.run {
                    onSentenceProcessed(processed)
                }
                currentLineIndex += 1
                logger.debug("Processed final sentence from buffer")
            } else {
                logger.warning("Could not parse remaining buffer as JSON: \(remainingBuffer)")
            }
        }
        
        logger.debug("Completed processing with \(currentLineIndex) sentences processed out of \(texts.count)")
    }
    
    private func processChunkStreaming(
        _ texts: [String],
        startIndex: Int,
        script: ChineseScript,
        apiKey: String,
        onSentenceProcessed: @escaping (StreamingProcessedSentence) -> Void
    ) async throws {
        logger.debug("Processing chunk starting at index \(startIndex) with \(texts.count) texts")
        
        let scriptDescription = script == .simplified ? "Simplified Chinese" : "Traditional Chinese"
        
        let numberedTexts = texts.enumerated().map { index, text in
            "\(index + 1). \(text)"
        }.joined(separator: "\n")
        
        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are a Chinese language expert. For each line of \(scriptDescription) text provided, generate:
                    1. Pinyin with tone marks (one syllable per character, separated by spaces)
                    2. English translation
                    
                    Output EXACTLY one JSON object per input line, each on its own line (JSON Lines format).
                    Each line should be a complete, valid JSON object like this:
                    {"pinyin": "pīn yīn", "english": "English translation"}
                    
                    IMPORTANT:
                    - Output one JSON object per line, NOT an array
                    - Each JSON object must be on a single line
                    - Do not include line numbers in the output
                    - Process lines in the exact order provided
                    - Output ONLY the JSON objects, no other text or formatting
                    """
                ],
                [
                    "role": "user",
                    "content": numberedTexts
                ]
            ],
            "temperature": 0,
            "max_tokens": 500,
            "stream": true
        ]
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ChineseProcessingError.apiError
        }
        
        var buffer = ""
        var currentLineIndex = 0
        
        for try await line in bytes.lines {
            // Parse SSE format
            guard line.hasPrefix("data: ") else { 
                logger.debug("Skipping non-data line: \(line)")
                continue 
            }
            let jsonString = String(line.dropFirst(6))
            
            if jsonString == "[DONE]" { 
                logger.debug("Stream completed")
                break 
            }
            
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                logger.debug("Failed to parse streaming chunk: \(jsonString)")
                continue
            }
            
            buffer += content
            logger.debug("Buffer updated with content: \(content)")
            
            // Try to extract complete JSON lines from buffer
            while let newlineRange = buffer.range(of: "\n") {
                let jsonLine = String(buffer[..<newlineRange.lowerBound])
                buffer = String(buffer[newlineRange.upperBound...])
                
                let trimmedLine = jsonLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedLine.isEmpty {
                    logger.debug("Attempting to parse JSON line: \(trimmedLine)")
                    
                    if let lineData = trimmedLine.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: String],
                       let pinyinString = parsed["pinyin"],
                       let english = parsed["english"],
                       currentLineIndex < texts.count {
                        
                        let pinyinArray = pinyinString.components(separatedBy: " ").filter { !$0.isEmpty }
                        
                        let processed = StreamingProcessedSentence(
                            chinese: texts[currentLineIndex],
                            pinyin: pinyinArray,
                            english: english,
                            index: startIndex + currentLineIndex
                        )
                        
                        logger.debug("Successfully parsed sentence \(currentLineIndex + 1): \(english)")
                        
                        // Call callback on main thread
                        await MainActor.run {
                            onSentenceProcessed(processed)
                        }
                        
                        currentLineIndex += 1
                    } else {
                        logger.warning("Failed to parse JSON line: \(trimmedLine)")
                    }
                }
            }
        }
        
        // Process any remaining buffer
        let remainingBuffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainingBuffer.isEmpty {
            logger.debug("Processing remaining buffer: \(remainingBuffer)")
            
            if let lineData = remainingBuffer.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: String],
               let pinyinString = parsed["pinyin"],
               let english = parsed["english"],
               currentLineIndex < texts.count {
                
                let pinyinArray = pinyinString.components(separatedBy: " ").filter { !$0.isEmpty }
                
                let processed = StreamingProcessedSentence(
                    chinese: texts[currentLineIndex],
                    pinyin: pinyinArray,
                    english: english,
                    index: startIndex + currentLineIndex
                )
                
                await MainActor.run {
                    onSentenceProcessed(processed)
                }
                
                logger.debug("Processed final sentence from buffer")
            } else {
                logger.warning("Could not parse remaining buffer as JSON: \(remainingBuffer)")
            }
        }
        
        logger.debug("Completed processing chunk with \(currentLineIndex) sentences processed")
    }
}