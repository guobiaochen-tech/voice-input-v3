import Foundation

/// 管理 prompts/ 目录下的风格与翻译 md 提示词。
///
/// 设计：
/// - 首次运行写出默认 md（已存在不覆盖，尊重用户的修改/删除）
/// - 运行时扫描目录动态生成下拉选项：用户新增 md = 新增选项
/// - 读取某项时优先读 md，文件缺失或为空则用内置默认兜底（选项不会因删文件而消失，只是回到默认提示词）
///
/// md 内容约定：
/// - 风格 md 只写"该风格的语气描述"，不含任务指令（改写语气 / 生成回复 两条流程共用）
/// - 翻译 md 写针对该语言的翻译指令
enum PromptManager {

    static var rootDir: String { ensureAppDataDir() + "/prompts" }
    static var stylesDir: String { rootDir + "/styles" }
    static var translateDir: String { rootDir + "/translate" }

    // MARK: - 内置默认（中文），顺序即下拉默认顺序

    private static let defaultStyles: [(name: String, prompt: String)] = [
        ("高情商", """
接住对方的情绪，再轻轻表达自己的态度。像懂分寸的朋友，体面、有温度，不冷场也不讨好。
多用短句和语气词。不说教、不分析、不「我建议」。
示例语气：哈哈这事儿确实头疼，不过你也别太往心里去，先缓一缓再说？
"""),
        ("幽默", """
用轻松俏皮的方式化解，可以自嘲、玩梗、抖个小机灵，让人笑出来就赢了。不强行搞笑、不拿对方开玩笑。
示例语气：好家伙，你这运气也是没谁了，要不要我传授你一下我的避雷秘籍（其实也没有
"""),
        ("暖男", """
温柔体贴，让对方感觉被放在心尖上。主动关心细节，语气软，像很在意你的人。
但别变成说教或爹味，是陪伴不是指导。
示例语气：呀，难受吗？快去躺着别动了，我给你点了杯热的一会儿到，乖乖休息～
"""),
        ("暧昧拉扯", """
若即若离，带着试探和撩拨，话里有话，制造心跳感。把球踢回去，不轻易表态，留点想象空间。
不轻浮、不油腻、不直球。
示例语气：梦到我？那得看你梦里的我对咋样了，不然我可不好说哦～
"""),
        ("情场高手", """
自信从容，懂节奏，进退有度。会撩但不油腻，让对方既被吸引又被尊重，有一种恰到好处的吸引力。
示例语气：认真问的啊？那我也认真答——你身上有股让人想多了解的劲儿，挺难得的。
"""),
        ("温柔大叔", """
沉稳包容，语气温和有安全感，像成熟可靠的人。给方向但不说教，是过来人的理解与托底。
示例语气：别急着要答案，迷茫是正常的。先把手头的事做好，慢慢会清晰的，急不来。
"""),
        ("有梗大王", """
网感强，用流行梗、热词、神回复，懂年轻人语境，表达又皮又有分寸。吐槽到位、金句频出。
示例语气：老板这饼烙了三年了，比我家祖传的还久，下季度咱直接众筹买个团队头衔算了😂
"""),
        ("情绪价值", """
先共情、先接住，让对方感觉被深深理解。认可 ta 的情绪，别急着讲道理，给肯定和陪伴。
示例语气：唉，哭出来就好了，能感觉到你压力有多大。你不是没用，你只是太累了，先别扛着了行吗？
"""),
        ("高情商拒绝", """
体面说「不」。先理解对方，再温和但明确地拒绝，守住边界又不伤和气。不绕弯子也不生硬。
示例语气：诶这个真有点为难，最近我也紧巴巴的，怕帮不上反而耽误你。要不咱一起想想别的招？
"""),
        ("成熟稳重", """
理性克制、条理清晰，但不冷漠。帮对方理清思路，直给关键点，不废话、不绕。
像靠谱的合作者，不情绪化。
示例语气：两个 offer 别急着定，先把「你最在意什么」排个序，钱、成长、生活，哪个第一？
"""),
    ]

    private static let defaultTranslate: [(name: String, prompt: String)] = [
        ("英文", "把下面的文本翻译成自然、地道的英文，保持原意和语气，只输出译文，不要解释、不要加引号。"),
        ("日文", "把下面的文本翻译成自然、地道的日文（按语境选择合适的文体），保持原意，只输出译文，不要解释。"),
        ("韩文", "把下面的文本翻译成自然、地道的韩文，保持原意和语气，只输出译文，不要解释。"),
        ("德文", "把下面的文本翻译成自然、地道的德文，保持原意和语气，只输出译文，不要解释。"),
    ]

    // MARK: - 首次写出默认 md

    /// 启动时调用：确保默认 md 存在，已存在的不覆盖。
    static func ensureDefaults() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: stylesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: translateDir, withIntermediateDirectories: true)
        for (name, prompt) in defaultStyles {
            writeDefault(stylesDir, name: name, content: prompt)
        }
        for (name, prompt) in defaultTranslate {
            writeDefault(translateDir, name: name, content: prompt)
        }
    }

    private static func writeDefault(_ dir: String, name: String, content: String) {
        let path = dir + "/" + name + ".md"
        guard !FileManager.default.fileExists(atPath: path) else { return }
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - 扫描目录（动态生成下拉选项）

    /// 可用风格列表：内置默认项按固定顺序排前，用户新增项按字母序排后。
    static func availableStyles() -> [String] {
        listDir(stylesDir, defaultNames: defaultStyles.map { $0.name })
    }

    /// 可用翻译语言列表。
    static func availableTranslateLangs() -> [String] {
        listDir(translateDir, defaultNames: defaultTranslate.map { $0.name })
    }

    private static func listDir(_ dir: String, defaultNames: [String]) -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return defaultNames }
        let names = Set(files.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) })
        let ordered = defaultNames.filter { names.contains($0) }            // 内置项保持顺序
        let extra = names.filter { !defaultNames.contains($0) }.sorted()    // 用户新增项
        return ordered + extra
    }

    // MARK: - 读取 prompt（md 优先，缺失用内置默认兜底）

    static func stylePrompt(_ name: String) -> String {
        load(stylesDir, name: name, defaults: defaultStyles)
    }

    static func translatePrompt(_ name: String) -> String {
        load(translateDir, name: name, defaults: defaultTranslate)
    }

    private static func load(_ dir: String, name: String,
                             defaults: [(name: String, prompt: String)]) -> String {
        let path = dir + "/" + name + ".md"
        if let s = try? String(contentsOfFile: path, encoding: .utf8),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return defaults.first { $0.name == name }?.prompt ?? defaults.first?.prompt ?? ""
    }
}
