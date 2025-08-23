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
        s2tMapping = [
            "爱": "愛", "碍": "礙", "袄": "襖", "肮": "骯", "熬": "熬",
            "罢": "罷", "坝": "壩", "摆": "擺", "败": "敗", "颁": "頒",
            "办": "辦", "绊": "絆", "帮": "幫", "绑": "綁", "镑": "鎊",
            "谤": "謗", "剥": "剝", "饱": "飽", "宝": "寶", "报": "報",
            "鲍": "鮑", "爆": "爆", "杯": "盃", "贝": "貝", "备": "備",
            "惫": "憊", "背": "背", "钡": "鋇", "狈": "狽", "贝": "貝",
            "辈": "輩", "奔": "奔", "笨": "笨", "绷": "繃", "泵": "泵",
            "边": "邊", "编": "編", "贬": "貶", "变": "變", "辩": "辯",
            "辫": "辮", "标": "標", "鳖": "鱉", "别": "別", "濒": "瀕",
            "滨": "濱", "宾": "賓", "饼": "餅", "并": "並", "拨": "撥",
            "钵": "缽", "铂": "鉑", "驳": "駁", "补": "補", "财": "財",
            "采": "採", "彩": "彩", "菜": "菜", "参": "參", "蚕": "蠶",
            "残": "殘", "惭": "慚", "惨": "慘", "灿": "燦", "苍": "蒼"
        ]
        
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