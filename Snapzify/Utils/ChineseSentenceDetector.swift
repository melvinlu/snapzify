import Foundation

struct ChineseSentenceDetector {
    // Chinese sentence delimiters
    private static let chineseDelimiters: Set<Character> = [
        "。", "！", "？", "；",  // Chinese punctuation
        ".", "!", "?", ";",      // English punctuation that might be used
        "\n"                     // Newlines also separate sentences
    ]
    
    // Detect if a character is Chinese
    private static func isChineseCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        
        // CJK Unified Ideographs ranges
        return (value >= 0x4E00 && value <= 0x9FFF) ||  // Main block
               (value >= 0x3400 && value <= 0x4DBF) ||  // Extension A
               (value >= 0x20000 && value <= 0x2A6DF) || // Extension B
               (value >= 0x2A700 && value <= 0x2B73F) || // Extension C
               (value >= 0x2B740 && value <= 0x2B81F) || // Extension D
               (value >= 0x2B820 && value <= 0x2CEAF) || // Extension E
               (value >= 0xF900 && value <= 0xFAFF) ||  // Compatibility
               (value >= 0x2F800 && value <= 0x2FA1F)   // Compatibility Supplement
    }
    
    // Extract Chinese sentences from text
    static func extractSentences(from text: String) -> [String] {
        var sentences: [String] = []
        var currentSentence = ""
        var hasChineseContent = false
        
        for char in text {
            currentSentence.append(char)
            
            if isChineseCharacter(char) {
                hasChineseContent = true
            }
            
            // Check if we hit a delimiter
            if chineseDelimiters.contains(char) {
                let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && hasChineseContent {
                    sentences.append(trimmed)
                }
                currentSentence = ""
                hasChineseContent = false
            }
        }
        
        // Add any remaining sentence
        let trimmed = currentSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && hasChineseContent {
            sentences.append(trimmed)
        }
        
        return sentences
    }
    
    // Find which sentence a tap location corresponds to
    static func findSentenceAtLocation(in text: String, at characterIndex: Int) -> String? {
        let sentences = extractSentences(from: text)
        var currentIndex = 0
        
        for sentence in sentences {
            let sentenceLength = sentence.count
            let sentenceEndIndex = currentIndex + sentenceLength
            
            if characterIndex >= currentIndex && characterIndex < sentenceEndIndex {
                return sentence
            }
            
            currentIndex = sentenceEndIndex
            
            // Account for delimiters between sentences
            let remainingText = String(text.dropFirst(currentIndex))
            if let nextSentenceStart = remainingText.firstIndex(where: { !chineseDelimiters.contains($0) && !$0.isWhitespace }) {
                let delimiterLength = remainingText.distance(from: remainingText.startIndex, to: nextSentenceStart)
                currentIndex += delimiterLength
            }
        }
        
        // If no sentence found, return the first sentence with Chinese content
        return sentences.first
    }
    
    // Split text into tappable segments
    static func createTappableSegments(from text: String) -> [(text: String, isChinese: Bool)] {
        let sentences = extractSentences(from: text)
        var segments: [(text: String, isChinese: Bool)] = []
        var processedLength = 0
        
        for sentence in sentences {
            // Find the sentence in the original text to preserve formatting
            if let range = text.range(of: sentence, range: text.index(text.startIndex, offsetBy: processedLength)..<text.endIndex) {
                // Add any text before this sentence (like spaces or punctuation)
                let startOffset = text.distance(from: text.startIndex, to: range.lowerBound)
                if startOffset > processedLength {
                    let beforeText = String(text[text.index(text.startIndex, offsetBy: processedLength)..<range.lowerBound])
                    if !beforeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        segments.append((text: beforeText, isChinese: false))
                    }
                }
                
                // Add the Chinese sentence
                segments.append((text: sentence, isChinese: true))
                processedLength = text.distance(from: text.startIndex, to: range.upperBound)
            }
        }
        
        // Add any remaining text
        if processedLength < text.count {
            let remainingText = String(text.dropFirst(processedLength))
            if !remainingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append((text: remainingText, isChinese: false))
            }
        }
        
        // If no Chinese sentences found, return the whole text as non-tappable
        if segments.isEmpty {
            return [(text: text, isChinese: false)]
        }
        
        return segments
    }
}