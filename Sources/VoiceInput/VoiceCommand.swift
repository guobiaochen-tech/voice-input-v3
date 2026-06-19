import Foundation

enum VoiceCommand {
    case normal(text: String)
    case reply(intent: String)
}

struct VoiceCommandParser {
    private static let replyPrefix = "帮我回复"

    /// 开头的语气词（ASR 常见噪声）。只剥这些，命令词本身和后面的内容绝不改动，触发词不放宽。
    private static let fillers = ["嗯", "啊", "呃", "哦", "那个", "就是", "然后", "我说", "你帮我", "请帮我", "麻烦帮我"]

    /// 命令分隔符：用于剥离开头标点、以及意图首尾标点
    private static let commandSeparators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "，,。.:：；;、!！?？~～"))

    /// 解析语音文本。只认"帮我回复"这四个字作为回复命令。
    /// 唯一容错：剥离开头的语气词和标点（应对 ASR 识别噪声），但绝不越过命令词、绝不放宽触发词。
    /// - "嗯,帮我回复,夸她" → 剥掉开头"嗯," → 识别 → 意图"夸她"
    /// - "帮我回复" → 识别 → 意图空
    /// - "帮我回一下" / "帮我恢复" / "帮我 回复" → 不识别（只认连续的"帮我回复"4 字）
    static func parse(_ text: String) -> VoiceCommand {
        let s = stripLeadingFillerAndPunct(text)
        if s.hasPrefix(replyPrefix) {
            let rawIntent = String(s.dropFirst(replyPrefix.count))
            let intent = rawIntent.trimmingCharacters(in: commandSeparators)
            return .reply(intent: intent)
        }
        return .normal(text: text)
    }

    /// 输出兜底：检测最终待输出的文本是否就是泄漏出来的"帮我回复"命令词。
    /// 命中 → 返回命令词后的意图（纯命令词返回空串）；未命中 → 返回 nil。
    /// 触发词判定与 parse 完全一致，不放宽（只剥开头语气词/标点，中间噪声和错字不认）。
    /// 用途：parse 万一漏判走了 normal 分支、或未来改动引入泄漏时，在粘贴前把命令词拦住、
    /// 纠正回回复流程，绝不让"帮我回复"原话粘贴出去。
    static func leakedReplyIntent(_ text: String) -> String? {
        let s = stripLeadingFillerAndPunct(text)
        guard s.hasPrefix(replyPrefix) else { return nil }
        let rawIntent = String(s.dropFirst(replyPrefix.count))
        return rawIntent.trimmingCharacters(in: commandSeparators)
    }

    /// 反复剥离开头的语气词和标点，剥到命令词就停，绝不越过它。
    private static func stripLeadingFillerAndPunct(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return s }

        var changed = true
        while changed {
            changed = false
            if s.hasPrefix(replyPrefix) { break }   // 已到命令词，停

            // 先剥一个开头的标点/空白
            let afterPunct = s.trimmingCharacters(in: commandSeparators)
            if afterPunct != s && afterPunct.count < s.count {
                s = afterPunct
                changed = true
                if s.hasPrefix(replyPrefix) { break }
                continue
            }

            // 再剥一个开头的语气词
            for filler in fillers {
                if s.hasPrefix(filler) {
                    s = String(s.dropFirst(filler.count))
                    changed = true
                    break
                }
            }
            if s.hasPrefix(replyPrefix) { break }
        }
        return s
    }
}
