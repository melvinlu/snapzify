import Foundation

struct ChineseDetector {
    static func containsChinese(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // CJK Unified Ideographs
            if (0x4E00...0x9FFF).contains(scalar.value) ||
               (0x3400...0x4DBF).contains(scalar.value) ||
               (0x20000...0x2A6DF).contains(scalar.value) ||
               (0x2A700...0x2B73F).contains(scalar.value) ||
               (0x2B740...0x2B81F).contains(scalar.value) ||
               (0x2B820...0x2CEAF).contains(scalar.value) ||
               (0xF900...0xFAFF).contains(scalar.value) ||
               (0x2F800...0x2FA1F).contains(scalar.value) {
                return true
            }
        }
        return false
    }
}