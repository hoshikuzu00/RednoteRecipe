import Foundation

struct RecipeDraft: Equatable {
    var title: String
    var ingredients: [RecipeIngredient]
    var steps: [String]
    var tips: [String]
    var timeHints: [String]
    var sections: [RecipeSection]

    var allIngredients: [RecipeIngredient] {
        ingredients + sections.flatMap(\.ingredients)
    }

    var totalStepCount: Int {
        steps.count + sections.reduce(0) { $0 + $1.steps.count }
    }
}

struct RecipeIngredient: Equatable, Identifiable {
    let id = UUID()
    var name: String
    var amount: String?
    var unit: String?
    var rawLine: String
}

struct RecipeSection: Equatable, Identifiable {
    let id: UUID
    var title: String
    var ingredients: [RecipeIngredient]
    var steps: [String]

    init(
        id: UUID = UUID(),
        title: String,
        ingredients: [RecipeIngredient],
        steps: [String]
    ) {
        self.id = id
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
    }

    static func == (lhs: RecipeSection, rhs: RecipeSection) -> Bool {
        lhs.title == rhs.title &&
        lhs.ingredients == rhs.ingredients &&
        lhs.steps == rhs.steps
    }
}

enum RecipeParser {
    private static let ingredientHeaders = [
        "食材", "材料", "配料", "用料", "食材准备", "准备食材", "所需食材"
    ]

    private static let stepHeaders = [
        "步骤", "做法", "制作步骤", "烹饪步骤", "开始制作", "操作步骤"
    ]

    private static let tipHeaders = [
        "tips", "tip", "小贴士", "贴士", "备注", "注意", "注意事项", "建议", "提醒"
    ]

    private static let ingredientMixtureKeywords = [
        "酱汁", "醬汁", "酱料", "醬料", "料汁", "蘸料", "沾料", "腌料", "醃料",
        "调料", "調料", "面糊", "粉浆", "粉漿", "浆", "漿", "芡汁", "勾芡",
        "淀粉水", "澱粉水", "太白粉水", "水淀粉", "水澱粉", "糊"
    ]

    private static let ingredientLineSeparators = CharacterSet(charactersIn: "、，,/")

    private static let ratioRegex = try? NSRegularExpression(
        pattern: #"\d+\s*[:：/]\s*\d+"#,
        options: []
    )

    private static let socialNoisePhrases = [
        "点赞", "点个赞", "收藏", "关注", "评论区", "评论一下", "评论告诉我",
        "转发", "一键三连", "主页", "进主页", "私信", "不迷路", "下期见",
        "谢谢观看", "感谢关注", "扣1", "运气不会差", "运气都不差",
        "爱评论的人", "爱点赞的人", "愛評論的人", "愛點讚的人",
        "運氣不會差", "運氣都不差", "點讚", "點贊", "關注"
    ]

    private static let titleIntroPhrases = [
        "今天分享", "今日分享", "来做", "教你做", "教你们做", "分享一个",
        "分享一道", "分享一款", "安排一个", "安排一道", "试试这个"
    ]

    private static let titleNoisePhrases = [
        "超赞", "超讚", "真赞", "真讚", "绝了", "絕了", "太香了", "很香的喔",
        "巨好吃", "超好吃", "yummy", "delicious"
    ]

    private static let titleQualifierPhrases = [
        "简易版", "簡易版", "简单版", "簡單版", "家庭版", "家常版", "懒人版", "懶人版",
        "快手版", "低卡版", "复刻版", "復刻版", "自制版", "自製版", "零失败版", "零失敗版",
        "减脂版", "減脂版", "入门版", "入門版"
    ]

    private static let titleTrailingCommentaryMarkers = [
        "到底", "真的", "真是", "也太", "太香", "太绝", "太絕", "绝了", "絕了",
        "绝绝子", "絕絕子", "谁懂", "誰懂", "狠狠爱上", "狠狠愛上", "太上头", "太上頭"
    ]

    private static let dishActionWords = [
        "拌", "炒", "煎", "炸", "烤", "焖", "燜", "煮", "蒸", "炖", "燉",
        "卤", "滷", "卷", "夹", "夾", "盖", "配", "蘸", "炝", "煲"
    ]

    private static let ingredientOnlyTitleKeywords = [
        "辣椒面", "辣椒粉", "胡椒粉", "黑胡椒", "白胡椒", "孜然", "椒盐", "椒鹽",
        "蒜泥", "蒜蓉", "生抽", "老抽", "蚝油", "蠔油", "料酒", "香油", "芝麻油",
        "酱油", "醬油", "醋", "番茄酱", "番茄醬", "沙茶", "淀粉", "澱粉", "太白粉",
        "玉米淀粉", "玉米澱粉", "鸡精", "雞精", "味精"
    ]

    private static let dishNameSuffixes = [
        "鸡翅根", "鸡翅", "鸡腿", "鸡排", "鸡柳", "鸡胸", "鸡爪", "鸡块",
        "排骨", "里脊", "牛腩", "肥牛", "肉丸", "蛋挞", "蛋糕", "吐司",
        "三明治", "意面", "焖饭", "炒饭", "炒面", "凉面", "凉皮", "米线",
        "盖饭", "沙拉", "寿司", "披萨", "火锅", "豆腐", "茄子", "土豆",
        "卤味", "滷味",
        "丸子", "馄饨", "水饺", "锅贴", "煲", "锅", "饭", "面", "汤",
        "粥", "粉", "卷", "饼", "包", "羹", "虾", "鱼", "鸡", "鸭",
        "肉", "菜"
    ]

    private static let hashtagRegex = try? NSRegularExpression(
        pattern: #"[#＃]([^\s#＃]{2,24})"#,
        options: []
    )

    private static let dishNameRegex: NSRegularExpression? = {
        let suffixPattern = dishNameSuffixes
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")

        let pattern = #"([一-龥A-Za-z0-9]{2,24}(?:"# + suffixPattern + #"))"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let timeRegex = try? NSRegularExpression(
        pattern: #"(\d+(?:\s*[-~到]\s*\d+)?)\s*(分钟|分|小时|小時|min|mins|minute|minutes|秒|s|sec|secs)"#,
        options: [.caseInsensitive]
    )

    private static let temperatureRegex = try? NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(度|℃|°C|华氏度|F)"#,
        options: [.caseInsensitive]
    )

    static func parse(_ text: String) -> RecipeDraft {
        let lines = normalizedLines(from: text)
        guard !lines.isEmpty else {
            return RecipeDraft(
                title: "",
                ingredients: [],
                steps: [],
                tips: [],
                timeHints: [],
                sections: []
            )
        }

        let title = inferTitle(from: lines)
        let ingredients = inferIngredients(from: lines)
        var steps = inferSteps(from: lines)
        let tips = inferTips(from: lines)
        let timeHints = inferTimeHints(from: lines)

        if steps.isEmpty, !timeHints.isEmpty {
            steps = timeHints
        }

        return RecipeDraft(
            title: title,
            ingredients: ingredients,
            steps: steps,
            tips: sanitizedTips(tips),
            timeHints: timeHints,
            sections: []
        )
    }

    static func sanitizedTitle(_ candidate: String, fallback: String? = nil) -> String {
        var candidates: [String] = []

        if let extracted = bestDishNameCandidate(from: candidate) {
            candidates.append(extracted)
        }

        candidates.append(normalizedTitleCandidate(from: candidate))

        if let fallback {
            if let extractedFallback = bestDishNameCandidate(from: fallback) {
                candidates.append(extractedFallback)
            }

            candidates.append(normalizedTitleCandidate(from: fallback))
        }

        let filteredCandidates = (Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates)
            .filter(isReasonableDishTitle(_:))

        if let best = filteredCandidates.max(by: { titleScore($0) < titleScore($1) }) {
            return best
        }

        return normalizedTitleCandidate(from: candidate)
    }

    static func resolvedTitle(
        candidate: String,
        fallback: String? = nil,
        ingredientNames: [String] = []
    ) -> String {
        let normalizedCandidate = sanitizedTitle(candidate, fallback: fallback)
        let normalizedFallback = fallback.map { sanitizedTitle($0) } ?? ""

        let candidateRejected = shouldRejectTitle(
            normalizedCandidate,
            ingredientNames: ingredientNames
        )
        let fallbackRejected = shouldRejectTitle(
            normalizedFallback,
            ingredientNames: ingredientNames
        )

        if candidateRejected {
            if !normalizedFallback.isEmpty, !fallbackRejected {
                return normalizedFallback
            }

            if !normalizedFallback.isEmpty, titleScore(normalizedFallback) > titleScore(normalizedCandidate) {
                return normalizedFallback
            }
        }

        if normalizedCandidate.isEmpty {
            return normalizedFallback
        }

        if !normalizedFallback.isEmpty,
           !fallbackRejected,
           titleScore(normalizedFallback) >= titleScore(normalizedCandidate) + 4 {
            return normalizedFallback
        }

        return normalizedCandidate
    }

    static func sanitizedTips(_ tips: [String]) -> [String] {
        var results: [String] = []

        for tip in tips {
            let cleaned = cleanedTip(tip)
            guard !cleaned.isEmpty else { continue }
            guard !containsSocialNoise(cleaned) else { continue }

            if !results.contains(cleaned) {
                results.append(cleaned)
            }
        }

        return results
    }

    private static func normalizedLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "•", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func inferTitle(from lines: [String]) -> String {
        let titleCandidates = lines
            .prefix(15)
            .flatMap(titleCandidates(from:))

        if let bestCandidate = titleCandidates.max(by: { titleScore($0) < titleScore($1) }) {
            return sanitizedTitle(bestCandidate)
        }

        for line in lines.prefix(8) {
            let candidate = sanitizedTitle(line)
            if isReasonableDishTitle(candidate) {
                return candidate
            }
        }

        return sanitizedTitle(lines[0])
    }

    private static func inferIngredients(from lines: [String]) -> [RecipeIngredient] {
        var results: [RecipeIngredient] = []
        var isInsideIngredientSection = false

        for line in lines {
            if matchesAnyHeader(line, headers: ingredientHeaders) {
                isInsideIngredientSection = true
                continue
            }

            if matchesAnyHeader(line, headers: stepHeaders) {
                isInsideIngredientSection = false
            }

            let shouldTryParse = isInsideIngredientSection || looksLikeIngredient(line)
            guard shouldTryParse else {
                continue
            }

            let ingredients = parseIngredients(from: line)
            for ingredient in ingredients {
                if !results.contains(where: { $0.rawLine == ingredient.rawLine }) {
                    results.append(ingredient)
                }
            }
        }

        return results
    }

    private static func inferSteps(from lines: [String]) -> [String] {
        var steps: [String] = []
        var isInsideStepSection = false

        for line in lines {
            if matchesAnyHeader(line, headers: stepHeaders) {
                isInsideStepSection = true
                continue
            }

            if isInsideStepSection || looksLikeStep(line) {
                let cleaned = cleanedStep(line)
                if !cleaned.isEmpty {
                    appendStepLine(cleaned, to: &steps)
                }
            }
        }

        if !steps.isEmpty {
            return steps
        }

        var inferredSteps: [String] = lines
            .filter { looksLikeNarrativeStep($0) }
            .map(cleanedStep(_:))

        inferredSteps = mergeShortContinuationLines(inferredSteps)
        return inferredSteps
    }

    private static func inferTimeHints(from lines: [String]) -> [String] {
        var hints: [String] = []

        for line in lines {
            if let matches = matches(in: line, regex: timeRegex) {
                hints.append(contentsOf: matches)
            }

            if let matches = matches(in: line, regex: temperatureRegex) {
                hints.append(contentsOf: matches)
            }
        }

        return Array(NSOrderedSet(array: hints)) as? [String] ?? []
    }

    private static func inferTips(from lines: [String]) -> [String] {
        var tips: [String] = []
        var isInsideTipSection = false

        for line in lines {
            if matchesAnyHeader(line, headers: tipHeaders) {
                isInsideTipSection = true
                continue
            }

            if matchesAnyHeader(line, headers: ingredientHeaders + stepHeaders) {
                isInsideTipSection = false
            }

            if isInsideTipSection || looksLikeTip(line) {
                let cleaned = cleanedTip(line)
                guard !cleaned.isEmpty else { continue }
                if !tips.contains(cleaned) {
                    tips.append(cleaned)
                }
            }
        }

        return tips
    }

    private static func titleCandidates(from line: String) -> [String] {
        guard !matchesAnyHeader(line, headers: ingredientHeaders + stepHeaders + tipHeaders) else {
            return []
        }

        guard !containsSocialNoise(line) else {
            return []
        }

        var candidates: [String] = []
        candidates.append(contentsOf: hashtagCandidates(from: line))

        if let dishCandidate = bestDishNameCandidate(from: line) {
            candidates.append(dishCandidate)
        }

        if looksLikeTitle(line) {
            candidates.append(normalizedTitleCandidate(from: line))
        }

        let uniqueCandidates = Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
        return uniqueCandidates.filter(isReasonableDishTitle(_:))
    }

    private static func hashtagCandidates(from line: String) -> [String] {
        guard let hashtagRegex else { return [] }
        let range = NSRange(line.startIndex..., in: line)

        let candidates = hashtagRegex.matches(in: line, options: [], range: range).compactMap { match in
            capture(in: line, match: match, at: 1)
        }

        return candidates
            .map(normalizedTitleCandidate(from:))
            .filter(isReasonableDishTitle(_:))
    }

    private static func bestDishNameCandidate(from line: String) -> String? {
        let cleanedLine = normalizedTitleCandidate(from: line)
        guard let dishNameRegex else { return nil }
        let range = NSRange(cleanedLine.startIndex..., in: cleanedLine)

        var candidates: [String] = []

        candidates.append(contentsOf: dishPhraseCandidates(from: cleanedLine))

        candidates.append(
            contentsOf: dishNameRegex.matches(in: cleanedLine, options: [], range: range)
                .compactMap { match in
                    capture(in: cleanedLine, match: match, at: 1)
                }
                .map(normalizedTitleCandidate(from:))
                .filter(isReasonableDishTitle(_:))
        )

        let uniqueCandidates = Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates

        return uniqueCandidates.max(by: { titleScore($0) < titleScore($1) })
    }

    private static func dishPhraseCandidates(from line: String) -> [String] {
        guard !line.isEmpty else { return [] }

        let characters = Array(line)
        var results: [String] = []

        for actionWord in dishActionWords {
            guard let range = line.range(of: actionWord) else { continue }

            let lowerDistance = line.distance(from: line.startIndex, to: range.lowerBound)
            let upperDistance = line.distance(from: line.startIndex, to: range.upperBound)
            let leftStart = max(0, lowerDistance - 8)
            let rightEnd = min(characters.count, upperDistance + 8)
            let candidate = String(characters[leftStart..<rightEnd])
            let cleanedCandidate = normalizedTitleCandidate(from: candidate)

            if isReasonableDishTitle(cleanedCandidate) {
                results.append(cleanedCandidate)
            }
        }

        return results
    }

    private static func looksLikeTitle(_ line: String) -> Bool {
        if matchesAnyHeader(line, headers: ingredientHeaders + stepHeaders) {
            return false
        }

        if matchesAnyHeader(line, headers: tipHeaders) {
            return false
        }

        if containsSocialNoise(line) {
            return false
        }

        if looksLikeIngredient(line) || looksLikeStep(line) {
            return false
        }

        if titleIntroPhrases.contains(where: { line.contains($0) }) ||
            line.contains("教程") || line.contains("做法") || line.contains("快手") {
            return false
        }

        if titleNoisePhrases.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            return false
        }

        return line.count <= 30
    }

    private static func titleScore(_ line: String) -> Int {
        var score = 0

        if line.contains("#") {
            score += 4
        }

        if line.contains("饭") || line.contains("面") || line.contains("汤") || line.contains("鸡") ||
            line.contains("肉") || line.contains("鱼") || line.contains("虾") || line.contains("锅") ||
            line.contains("饼") || line.contains("蛋糕") || line.contains("豆腐") || line.contains("排骨") {
            score += 5
        }

        if line.count <= 14 {
            score += 3
        }

        if line.contains("一定要") || line.contains("绝了") || line.contains("巨好吃") || line.contains("安排") {
            score -= 4
        }

        if containsDishSuffix(line) {
            score += 8
        }

        if containsSocialNoise(line) {
            score -= 8
        }

        if titleNoisePhrases.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            score -= 8
        }

        if containsDishAction(line) {
            score += 8
        }

        if looksLikeIngredientOnlyTitle(line) {
            score -= 10
        }

        return score
    }

    private static func looksLikeIngredient(_ line: String) -> Bool {
        if line.count > 35 || line.contains("，") || line.contains("。") {
            return false
        }

        let unitTokens = [
            "克", "g", "kg", "毫升", "ml", "l", "勺", "大勺", "小勺",
            "茶匙", "汤匙", "个", "只", "片", "瓣", "根", "块", "盒",
            "袋", "颗", "适量", "少许"
        ]

        return line.range(of: #"\d"#, options: .regularExpression) != nil ||
            unitTokens.contains(where: { line.localizedCaseInsensitiveContains($0) })
    }

    private static func parseIngredients(from line: String) -> [RecipeIngredient] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let groupedIngredients = parseIngredientGroup(from: trimmed), !groupedIngredients.isEmpty {
            return groupedIngredients
        }

        if let ingredient = parseIngredient(from: trimmed) {
            return [ingredient]
        }

        return []
    }

    private static func parseIngredient(from line: String) -> RecipeIngredient? {
        let trimmed = line
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        if let compoundIngredient = parseCompoundIngredient(from: trimmed) {
            return compoundIngredient
        }

        let pattern = #"^\s*([^\d]{1,20}?)\s*(\d+(?:\.\d+)?)?\s*(克|g|kg|毫升|ml|l|勺|大勺|小勺|茶匙|汤匙|个|只|片|瓣|根|块|盒|袋|颗|适量|少许)?\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else {
            return nil
        }

        let name = capture(in: trimmed, match: match, at: 1)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !name.isEmpty, !matchesAnyHeader(name, headers: ingredientHeaders + stepHeaders) else {
            return nil
        }

        let amount = capture(in: trimmed, match: match, at: 2)
        let unit = capture(in: trimmed, match: match, at: 3)

        return RecipeIngredient(name: name, amount: amount, unit: unit, rawLine: trimmed)
    }

    private static func parseIngredientGroup(from line: String) -> [RecipeIngredient]? {
        guard line.rangeOfCharacter(from: ingredientLineSeparators) != nil else {
            return nil
        }

        guard !looksLikeStep(line), !looksLikeNarrativeStep(line) else {
            return nil
        }

        let fragments = line
            .split(whereSeparator: { character in
                character.unicodeScalars.contains { ingredientLineSeparators.contains($0) }
            })
            .map { fragment in
                cleanedIngredientFragment(String(fragment))
            }
            .filter { !$0.isEmpty }

        guard fragments.count >= 2 else {
            return nil
        }

        let parsed = fragments.compactMap { fragment -> RecipeIngredient? in
            if let compoundIngredient = parseCompoundIngredient(from: fragment) {
                return compoundIngredient
            }

            if let parsedIngredient = parseIngredientAtom(from: fragment) {
                return parsedIngredient
            }

            if looksLikePlainIngredientName(fragment) {
                return RecipeIngredient(name: fragment, amount: nil, unit: nil, rawLine: fragment)
            }

            return nil
        }

        return parsed.isEmpty ? nil : parsed
    }

    private static func parseIngredientAtom(from line: String) -> RecipeIngredient? {
        let trimmed = line
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        let pattern = #"^\s*([^\d]{1,20}?)\s*(\d+(?:\.\d+)?)?\s*(克|g|kg|毫升|ml|l|勺|大勺|小勺|茶匙|汤匙|个|只|片|瓣|根|块|盒|袋|颗|适量|少许)?\s*$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else {
            return nil
        }

        let name = capture(in: trimmed, match: match, at: 1)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !name.isEmpty, !matchesAnyHeader(name, headers: ingredientHeaders + stepHeaders) else {
            return nil
        }

        let amount = capture(in: trimmed, match: match, at: 2)
        let unit = capture(in: trimmed, match: match, at: 3)

        return RecipeIngredient(name: name, amount: amount, unit: unit, rawLine: trimmed)
    }

    private static func parseCompoundIngredient(from line: String) -> RecipeIngredient? {
        guard looksLikeCompoundIngredient(line) else {
            return nil
        }

        let normalized = line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        return RecipeIngredient(
            name: normalized,
            amount: nil,
            unit: nil,
            rawLine: normalized
        )
    }

    private static func looksLikeCompoundIngredient(_ line: String) -> Bool {
        guard !looksLikeStep(line) else { return false }
        guard !matchesAnyHeader(line, headers: ingredientHeaders + stepHeaders + tipHeaders) else {
            return false
        }

        let hasMixtureKeyword = ingredientMixtureKeywords.contains {
            line.localizedCaseInsensitiveContains($0)
        }
        let hasRatio = matches(in: line, regex: ratioRegex) != nil
        let hasDivider = line.contains(":") || line.contains("：") || line.contains("/") || line.contains("比")

        return (hasMixtureKeyword && hasDivider) || (hasMixtureKeyword && hasRatio)
    }

    private static func looksLikeStep(_ line: String) -> Bool {
        let stepPattern = #"^(第?\s*\d+\s*[步\.、:]?|[①②③④⑤⑥⑦⑧⑨⑩]|[\d]+\.)"#
        return line.range(of: stepPattern, options: .regularExpression) != nil
    }

    private static func looksLikeNarrativeStep(_ line: String) -> Bool {
        if line.count < 6 || line.count > 80 {
            return false
        }

        let cookingWords = [
            "加入", "放入", "倒入", "搅拌", "翻炒", "煮", "焖", "蒸",
            "烤", "空气炸", "腌制", "切", "下锅", "炒", "烧"
        ]

        return cookingWords.contains(where: { line.contains($0) })
    }

    private static func looksLikeTip(_ line: String) -> Bool {
        let tipWords = [
            "小贴士", "贴士", "tips", "建议", "注意", "提醒", "备注",
            "一定要", "不要", "更好吃", "更香", "更嫩", "去腥", "锁住", "口感"
        ]

        guard line.count <= 80 else { return false }
        guard !containsSocialNoise(line) else { return false }
        return tipWords.contains(where: { line.localizedCaseInsensitiveContains($0) })
    }

    private static func appendStepLine(_ line: String, to steps: inout [String]) {
        if let lastIndex = steps.indices.last,
           shouldAppendToPreviousStep(line) {
            steps[lastIndex] += "，" + line
            return
        }

        steps.append(line)
    }

    private static func mergeShortContinuationLines(_ steps: [String]) -> [String] {
        var merged: [String] = []

        for step in steps {
            if let lastIndex = merged.indices.last,
               shouldAppendToPreviousStep(step) {
                merged[lastIndex] += "，" + step
            } else {
                merged.append(step)
            }
        }

        return merged
    }

    private static func shouldAppendToPreviousStep(_ line: String) -> Bool {
        if line.count > 20 {
            return false
        }

        let continuationWords = [
            "分钟", "分", "小时", "秒", "度", "℃", "°C", "小火", "中火", "大火",
            "静置", "焖", "冷藏", "冷冻", "腌", "翻面", "预热", "再烤", "再煮"
        ]

        return continuationWords.contains(where: { line.contains($0) })
    }

    private static func cleanedStep(_ line: String) -> String {
        line
            .replacingOccurrences(
                of: #"^(第?\s*\d+\s*[步\.、:]?|[①②③④⑤⑥⑦⑧⑨⑩]|[\d]+\.)\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedTitle(_ line: String) -> String {
        line
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "＃", with: "")
            .replacingOccurrences(
                of: #"^(今天|今日|最近|给你们|给大家|来做|教你做|教你们做|分享(?:一个|一道|一款)?|安排(?:一个|一道|一款)?|试试这个)\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^(?:简易版|簡易版|简单版|簡單版|家庭版|家常版|懒人版|懶人版|快手版|低卡版|复刻版|復刻版|自制版|自製版|零失败版|零失敗版|减脂版|減脂版|入门版|入門版)\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"^(一个|一道|一款)\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(做法|教程|食谱)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?:到底|真的|真是|也太|太香|太绝|太絕|绝了|絕了|绝绝子|絕絕子|谁懂|誰懂|狠狠爱上|狠狠愛上|太上头|太上頭).*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "《》【】[]()（）:：-—·• "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedTip(_ line: String) -> String {
        let cleaned = line
            .replacingOccurrences(
                of: #"^(tips?|小贴士|贴士|备注|注意事项|注意|建议|提醒)\s*[:：]?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !containsSocialNoise(cleaned) else {
            return ""
        }

        return cleaned
    }

    private static func cleanedIngredientFragment(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"（[^）]*）"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:·•!！ "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTitleCandidate(from line: String) -> String {
        cleanedTitle(line)
    }

    private static func isReasonableDishTitle(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard value.count <= 24 else { return false }
        guard !containsSocialNoise(value) else { return false }
        guard !titleNoisePhrases.contains(where: { value.localizedCaseInsensitiveContains($0) }) else { return false }
        guard !titleIntroPhrases.contains(where: { value.contains($0) }) else { return false }
        guard !titleQualifierPhrases.contains(where: { value.contains($0) }) else { return false }
        guard !value.contains("教程"), !value.contains("做法"), !value.contains("评论") else { return false }
        guard !looksLikeIngredient(value), !looksLikeStep(value) else { return false }
        guard !looksLikeIngredientOnlyTitle(value) || containsDishAction(value) else { return false }
        return true
    }

    private static func containsSocialNoise(_ line: String) -> Bool {
        socialNoisePhrases.contains { line.localizedCaseInsensitiveContains($0) }
    }

    private static func containsDishSuffix(_ line: String) -> Bool {
        dishNameSuffixes.contains { line.contains($0) }
    }

    private static func containsDishAction(_ line: String) -> Bool {
        dishActionWords.contains { line.contains($0) }
    }

    private static func looksLikeIngredientOnlyTitle(_ value: String) -> Bool {
        ingredientOnlyTitleKeywords.contains {
            value.localizedCaseInsensitiveContains($0)
        } && !containsDishAction(value)
    }

    private static func shouldRejectTitle(_ value: String, ingredientNames: [String]) -> Bool {
        guard !value.isEmpty else { return true }

        if looksLikeIngredientOnlyTitle(value) {
            return true
        }

        if ingredientNames.contains(where: { normalizedTitleCandidate(from: $0) == value }),
           !containsDishAction(value),
           !containsDishSuffix(value) {
            return true
        }

        return false
    }

    private static func looksLikePlainIngredientName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard value.count <= 18 else { return false }
        guard !looksLikeStep(value), !looksLikeNarrativeStep(value) else { return false }
        guard !containsSocialNoise(value) else { return false }

        let actionWords = ["加入", "放入", "倒入", "焯", "煮", "炒", "炸", "烤", "焖", "备用", "拌匀", "搅拌", "分钟", "一下"]
        guard !actionWords.contains(where: { value.contains($0) }) else { return false }

        return true
    }

    private static func matchesAnyHeader(_ line: String, headers: [String]) -> Bool {
        headers.contains { header in
            let lowered = line.lowercased()
            return lowered == header.lowercased() || lowered.hasPrefix(header.lowercased() + ":") || lowered.hasPrefix(header.lowercased() + "：")
        }
    }

    private static func matches(in string: String, regex: NSRegularExpression?) -> [String]? {
        guard let regex else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        let results = regex.matches(in: string, options: [], range: range)

        guard !results.isEmpty else { return nil }

        return results.compactMap { result in
            guard let matchRange = Range(result.range, in: string) else { return nil }
            return String(string[matchRange])
        }
    }

    private static func capture(in string: String, match: NSTextCheckingResult, at index: Int) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: string) else {
            return nil
        }

        let value = String(string[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
