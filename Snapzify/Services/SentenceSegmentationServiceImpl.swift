import Foundation
import NaturalLanguage

class SentenceSegmentationServiceImpl: SentenceSegmentationService {
    private let sentenceEnders = CharacterSet(charactersIn: "。！？；：…")
    private let quotationMarks = CharacterSet(charactersIn: "」』\"》）】")
    
    func segmentIntoSentences(from lines: [OCRLine]) async -> [(text: String, bbox: CGRect)] {
        var sentences: [(text: String, bbox: CGRect)] = []
        
        // Simply treat each OCR line as its own sentence
        // The OCR has already done the line segmentation for us
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sentences.append((text: text, bbox: line.bbox))
            }
        }
        
        return sentences
    }
    
    func tokenize(_ sentence: String) async -> [Token] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = sentence
        
        var tokens: [Token] = []
        tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { tokenRange, _ in
            let token = String(sentence[tokenRange])
            tokens.append(Token(text: token))
            return true
        }
        
        return mergeTokens(tokens)
    }
    
    private func mergeTokens(_ tokens: [Token]) -> [Token] {
        var merged: [Token] = []
        var i = 0
        
        while i < tokens.count {
            var current = tokens[i]
            
            if i < tokens.count - 1 {
                let next = tokens[i + 1]
                let combined = current.text + next.text
                
                if shouldMerge(current.text, next.text) {
                    current = Token(text: combined)
                    i += 1
                }
            }
            
            merged.append(current)
            i += 1
        }
        
        return merged
    }
    
    private func shouldMerge(_ first: String, _ second: String) -> Bool {
        let commonWords = ["你好", "谢谢", "再见", "什么", "怎么", "为什么", "哪里", "多少"]
        let combined = first + second
        return commonWords.contains(combined)
    }
}