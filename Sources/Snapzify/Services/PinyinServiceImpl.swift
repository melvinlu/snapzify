import Foundation

class PinyinServiceImpl: PinyinService {
    private let cache = NSCache<NSString, NSArray>()
    private var pinyinMap: [String: [String]] = [:]
    
    init() {
        cache.countLimit = 1000
        loadPinyinMap()
    }
    
    private func loadPinyinMap() {
        pinyinMap = [
            "你": ["nǐ"], "好": ["hǎo", "hào"], "我": ["wǒ"],
            "是": ["shì"], "在": ["zài"], "的": ["de", "dí", "dì"],
            "了": ["le", "liǎo"], "有": ["yǒu"], "和": ["hé", "hè", "huó"],
            "人": ["rén"], "这": ["zhè"], "中": ["zhōng", "zhòng"],
            "大": ["dà", "dài"], "为": ["wéi", "wèi"], "上": ["shàng"],
            "个": ["gè"], "国": ["guó"], "地": ["dì", "de"],
            "到": ["dào"], "他": ["tā"], "时": ["shí"], "来": ["lái"],
            "用": ["yòng"], "们": ["men"], "生": ["shēng"], "出": ["chū"],
            "就": ["jiù"], "分": ["fēn", "fèn"], "对": ["duì"],
            "成": ["chéng"], "会": ["huì", "kuài"], "可": ["kě"],
            "主": ["zhǔ"], "发": ["fā", "fà"], "年": ["nián"],
            "动": ["dòng"], "同": ["tóng"], "工": ["gōng"],
            "也": ["yě"], "能": ["néng"], "下": ["xià"], "过": ["guò"],
            "子": ["zǐ", "zi"], "说": ["shuō"], "产": ["chǎn"],
            "种": ["zhǒng", "zhòng"], "面": ["miàn"], "而": ["ér"],
            "方": ["fāng"], "后": ["hòu"], "多": ["duō"], "定": ["dìng"],
            "行": ["xíng", "háng"], "学": ["xué"], "法": ["fǎ"],
            "所": ["suǒ"], "民": ["mín"], "得": ["dé", "děi", "de"],
            "经": ["jīng"], "十": ["shí"], "三": ["sān"], "之": ["zhī"],
            "进": ["jìn"], "着": ["zhe", "zháo", "zhāo", "zhuó"],
            "等": ["děng"], "部": ["bù"], "度": ["dù"], "家": ["jiā"],
            "长": ["cháng", "zhǎng"], "重": ["zhòng", "chóng"],
            "作": ["zuò"], "要": ["yào", "yāo"], "被": ["bèi"],
            "应": ["yīng", "yìng"], "乐": ["lè", "yuè"],
            "还": ["hái", "huán"], "没": ["méi", "mò"],
            "看": ["kàn", "kān"], "着": ["zhe", "zháo", "zhāo"],
            "只": ["zhǐ", "zhī"], "把": ["bǎ", "bà"],
            "给": ["gěi", "jǐ"], "让": ["ràng"], "被": ["bèi"],
            "那": ["nà", "nèi"], "得": ["dé", "děi", "de"],
            "都": ["dōu", "dū"], "与": ["yǔ", "yù", "yú"],
            "向": ["xiàng"], "她": ["tā"], "如": ["rú"],
            "已": ["yǐ"], "些": ["xiē"], "此": ["cǐ"],
            "但": ["dàn"], "两": ["liǎng"], "次": ["cì"],
            "于": ["yú"], "真": ["zhēn"], "或": ["huò"],
            "把": ["bǎ"], "更": ["gèng", "gēng"], "将": ["jiāng", "jiàng"]
        ]
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