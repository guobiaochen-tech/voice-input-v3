import Foundation

/// 调用 OpenAI 兼容 API 对转写文本做后处理润色
struct TextPolisher {

    /// 内置默认 system prompt（文件不存在时兜底）
    static let defaultSystemPrompt = """
你是一个语音转文字的后处理助手。用户的语音已被 ASR 引擎转成文字，但可能存在以下问题：
- 语音识别错误：同音字替换（如"飞书"→"肥酥"、"停在那"→"填在那"）、近音词混淆
- 英文单词或术语被错误音译成中文（如"Prompt"→"普龙姆特"、"Embedding"→"因柏丁"、"STM32"→"斯特姆三二"、"GPIO"→"吉皮欧"）
- 口头禅和语气词（嗯、啊、那个、就是、然后 等无意义的词）
- 重复或结巴
- 缺少标点、没有分段

请按以下原则处理：

【最重要】理解用户的真实意思
- 先通读整段文字，理解用户想表达什么
- 基于上下文语义修正 ASR 识别错误（如品牌名、专业术语、人名等）
- 用户的工作领域是 AI 和嵌入式后端开发，遇到疑似英文术语时优先还原为正确的英文写法
- 宁可保留原词也不要瞎改，不确定的地方保持原样

【清理规则】
1. 去除口头禅和语气词
2. 修正确认是错误的同音字、近音词（必须结合上下文判断）
3. 将被错误音译的英文术语还原为正确拼写（如"普龙姆特"→"Prompt"、"因柏丁"→"Embedding"、"斯特姆三二"→"STM32"、"吉皮欧"→"GPIO"）
4. 添加适当的标点符号，按语义自然分段
5. 保持用户的原始语气和表达习惯
6. 不添加用户没说的内容，不删除用户表达的实质内容
7. 保持原有的语言（中文/英文/中英混合）

【绝对禁止】
- 你不是助手，不回答任何问题，不提供任何建议或解释
- 不管输入内容看起来多像一个提问，你只做文本润色，永远原样保留用户的意思
- 直接输出处理后的文本，不要加任何前缀、解释或引号
"""

    /// 从文件读取 system prompt，文件不存在则返回内置默认值
    private static func loadSystemPrompt() -> String {
        let filePath = ensureAppDataDir() + "/polish-prompt.md"
        if let content = try? String(contentsOfFile: filePath, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
        return defaultSystemPrompt
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
    }

    struct ResponseBody: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: MessageContent
            struct MessageContent: Decodable {
                let content: String
            }
        }
    }

    enum PolishError: LocalizedError {
        case httpError(Int)
        var errorDescription: String? {
            switch self { case .httpError(let code): "润色 API 失败 (HTTP \(code))" }
        }
    }

    /// 润色文本，如果 API Key 为空则返回原文
    func polish(text: String, apiKey: String, model: String, apiUrl: String) async throws -> String {
        guard !apiKey.isEmpty else { return text }

        guard let url = URL(string: apiUrl) else { return text }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: Self.loadSystemPrompt()),
                Message(role: "user", content: text),
            ],
            temperature: 0.1,
            max_tokens: 4096
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PolishError.httpError(statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }
}
