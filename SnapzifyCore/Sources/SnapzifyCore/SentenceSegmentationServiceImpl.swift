import Foundation
import NaturalLanguage

class SentenceSegmentationServiceImpl: SentenceSegmentationService {
    private let sentenceEnders = CharacterSet(charactersIn: "。！？；：…")
    private let quotationMarks = CharacterSet(charactersIn: "」』\"》）】")
    
    func segmentIntoSentences(from lines: [OCRLine]) async -> [(text: String, bbox: CGRect)] {
        var sentences: [(text: String, bbox: CGRect)] = []
        var currentSentence = ""
        var currentBoxes: [CGRect] = []
        
        for line in lines {
            let text = line.text
            var buffer = ""
            
            for char in text {
                buffer.append(char)
                
                if sentenceEnders.contains(char.unicodeScalars.first!) {
                    if let next = text.firstIndex(of: char)?.utf16Offset(in: text),
                       next < text.count - 1 {
                        let nextChar = text[text.index(text.startIndex, offsetBy: next + 1)]
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