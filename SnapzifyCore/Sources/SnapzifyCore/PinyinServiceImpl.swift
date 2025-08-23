import Foundation

class PinyinServiceImpl: PinyinService {
    private let cache = NSCache<NSString, NSArray>()
    private var pinyinMap: [String: [String]] = [:]
    
    init() {
        cache.countLimit = 1000
        loadPinyinMap()
    }
    
    private func loadPinyinMap() {
        pinyinMap = [:]
    }
    
    func getPinyin(for text: String, script: ChineseScript) async -> [String] {
        let cacheKey = "\(text):\(script.rawValue)" as NSString
        if let cached = cache.object(forKey: cacheKey) as? [String] {
            return cached
        }
        
        var textToProcess = text
        if script == .traditional {
            textToProcess = convertToSimplifiedForLookup(text)
        }
        
        let result = textToProcess.map { char -> String in
            let charStr = String(char)
            if let pinyinOptions = pinyinMap[charStr] {
                return pinyinOptions.first ?? charStr
            }
            return charStr
        }
        
        cache.setObject(result as NSArray, forKey: cacheKey)
        return result
    }
    
    func getPinyinForTokens(_ tokens: [Token], script: ChineseScript) async -> [String] {
        var result: [String] = []
        for token in tokens {
            let pinyinChars = await getPinyin(for: token.text, script: script)
            result.append(pinyinChars.joined(separator: ""))
        }
        return result
    }
    
    private func convertToSimplifiedForLookup(_ text: String) -> String {
        let t2sMap: [Character: Character] = [
            "愛": "爱", "礙": "碍", "襖": "袄", "骯": "肮",
            "罷": "罢", "壩": "坝", "擺": "摆", "敗": "败",
            "頒": "颁", "辦": "办", "絆": "绊", "幫": "帮",
            "綁": "绑", "鎊": "镑", "謗": "谤", "剝": "剥",
            "飽": "饱", "寶": "宝", "報": "报", "鮑": "鲍",
            "貝": "贝", "備": "备", "憊": "惫", "鋇": "钡",
            "狽": "狈", "輩": "辈", "繃": "绷", "邊": "边",
            "編": "编", "貶": "贬", "變": "变", "辯": "辩",
            "辮": "辫", "標": "标", "鱉": "鳖", "別": "别",
            "瀕": "濒", "濱": "滨", "賓": "宾", "餅": "饼",
            "並": "并", "撥": "拨", "缽": "钵", "鉑": "铂",
            "駁": "驳", "補": "补", "財": "财", "採": "采",
            "參": "参", "蠶": "蚕", "殘": "残", "慚": "惭",
            "慘": "惨", "燦": "灿", "蒼": "苍"
        ]
        
        return String(text.map { t2sMap[$0] ?? $0 })
    }
}
