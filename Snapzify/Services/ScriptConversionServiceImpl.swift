import Foundation

class ScriptConversionServiceImpl: ScriptConversionService {
    private let cache = NSCache<NSString, NSString>()
    private var s2tMapping: [String: String] = [:]
    private var t2sMapping: [String: String] = [:]
    
    init() {
        cache.countLimit = 500
        loadMappings()
    }
    
    private func loadMappings() {
        s2tMapping = [:]
        
        for (simplified, traditional) in s2tMapping {
            t2sMapping[traditional] = simplified
        }
    }
    
    func toSimplified(_ text: String) -> String {
        if let cached = cache.object(forKey: "s:\(text)" as NSString) {
            return cached as String
        }
        
        let result = text.map { char -> String in
            let charStr = String(char)
            return t2sMapping[charStr] ?? charStr
        }.joined()
        
        cache.setObject(result as NSString, forKey: "s:\(text)" as NSString)
        return result
    }
    
    func toTraditional(_ text: String) -> String {
        if let cached = cache.object(forKey: "t:\(text)" as NSString) {
            return cached as String
        }
        
        let result = text.map { char -> String in
            let charStr = String(char)
            return s2tMapping[charStr] ?? charStr
        }.joined()
        
        cache.setObject(result as NSString, forKey: "t:\(text)" as NSString)
        return result
    }
}
