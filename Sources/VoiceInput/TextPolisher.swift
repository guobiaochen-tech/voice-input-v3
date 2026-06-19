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
        let filePath = ensureAppDataDir() + "/prompts/polish-prompt.md"
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

    /// 根据用户选中的聊天上下文和口述意图生成一条可直接发送的回复。
    func composeReply(context: String, intent: String, style: String, apiKey: String, model: String, apiUrl: String) async throws -> String {
        guard !apiKey.isEmpty else { return intent }

        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIntent = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        let stylePrompt = PromptManager.stylePrompt(style)

        guard let url = URL(string: apiUrl) else { return cleanIntent }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let userPrompt = """
聊天上下文：
\(cleanContext.isEmpty ? "（用户没有选中聊天上下文）" : cleanContext)

回复风格：
\(stylePrompt)

用户口述意图：
\(cleanIntent.isEmpty ? "没有额外口述意图。请只根据聊天上下文判断对方想表达什么，并生成一条自然回复。" : cleanIntent)
"""

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: Self.replySystemPrompt),
                Message(role: "user", content: userPrompt),
            ],
            temperature: 0.7,
            max_tokens: 1024
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PolishError.httpError(statusCode)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? cleanIntent
    }

    /// 翻译：先润色（去口水词、纠错）再翻译成目标语言，一步输出最终译文
    func translate(text: String, lang: String, apiKey: String, model: String, apiUrl: String) async throws -> String {
        let system = """
你是一个语音转文字后处理助手，对用户的中文语音文本分两步处理，只输出最终结果：
1. 先基本润色：去除口头禅/语气词、修正同音错误、加标点分段（保持原意）
2. 再把润色后的文本翻译成目标语言

要求：
- 不要输出中间的润色结果，只输出最终译文
- 不要解释、不要加引号、不要加前缀
- 原文若中英混合，整体翻译成目标语言

\(PromptManager.translatePrompt(lang))
"""
        if let result = try await chat(system: system, user: text, apiKey: apiKey, model: model, apiUrl: apiUrl),
           !result.isEmpty {
            return result
        }
        return text
    }

    /// 通用聊天补全：发 system + user，返回文本；apiKey 为空或 URL 非法返回 nil
    private func chat(system: String, user: String, apiKey: String, model: String, apiUrl: String) async throws -> String? {
        guard !apiKey.isEmpty else { return nil }
        guard let url = URL(string: apiUrl) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let body = RequestBody(
            model: model,
            messages: [
                Message(role: "system", content: system),
                Message(role: "user", content: user),
            ],
            temperature: 0.1,
            max_tokens: 4096
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PolishError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 测 LLM 发问题+推理速度：发固定短测试 prompt，计时到收到完整响应。
    /// 返回 (totalMs, 回复字数)，失败返回 nil。
    struct LLMMeasureResult {
        let totalMs: Int
        let chars: Int
        var display: String { "延迟 \(totalMs)ms · \(chars) 字" }
    }

    func measureLatency(apiKey: String, model: String, apiUrl: String) async -> LLMMeasureResult? {
        guard !apiKey.isEmpty, !model.isEmpty, URL(string: apiUrl) != nil else { return nil }
        let start = Date()
        guard let reply = try? await chat(
            system: "你是一个测试助手，简短回复。",
            user: "你好",
            apiKey: apiKey, model: model, apiUrl: apiUrl
        ) else {
            return nil
        }
        let totalMs = Int(Date().timeIntervalSince(start) * 1000)
        return LLMMeasureResult(totalMs: totalMs, chars: reply.count)
    }

    /// 拉取该 API Key 下可用的模型列表（OpenAI 兼容 /models 端点）。
    /// 把 chat completions 的 url 末尾换成 /models。返回 nil 表示不支持/失败。
    static func fetchAvailableModels(apiKey: String, apiUrl: String) async -> [String]? {
        guard !apiKey.isEmpty, let url = modelsEndpoint(from: apiUrl) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            // OpenAI 兼容：{ "data": [ {"id": "model-name"}, ... ] }
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return decoded.data.map(\.id).sorted()
        } catch {
            return nil
        }
    }

    /// 把 chat completions 的 url 转成 /models 端点。
    /// 如 https://api.deepseek.com/chat/completions → https://api.deepseek.com/models
    private static func modelsEndpoint(from apiUrl: String) -> URL? {
        guard let base = URL(string: apiUrl) else { return nil }
        // 去掉路径里的 /chat/completions、/v1/chat/completions 等，保留 origin (+ /v1)
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        var segments = comps.path.split(separator: "/").map(String.init)
        // 倒着去掉 "completions"、"chat"
        while let last = segments.last, last == "completions" || last == "chat" {
            segments.removeLast()
        }
        // 若剩下不含 v1，且原本带 v1，保留 v1 前缀
        comps.path = "/" + segments.joined(separator: "/") + "/models"
        return comps.url
    }

    private struct ModelsResponse: Decodable {
        let data: [ModelItem]
        struct ModelItem: Decodable { let id: String }
    }

    private static let replySystemPrompt = """
你现在的身份就是用户本人。用户在聊天软件（微信/QQ）里收到了对方发来的消息，需要你帮 ta 写一条要发出去的回复。你不是 AI 助手，不要用助手口吻。

【最关键】写得像真人发的消息
- 用口语，像随手打出来的字，不要用书面语、不要用排比、不要用「首先/其次/最后」
- 只输出一条消息，像微信里打一次字发出去那样，不要用换行拆成多条
- 可以有语气词、口语化表达、轻微的不规范（省略号、～、哈哈 等）
- 不要解释、不要分析、不要说「我建议你」「你可以试试」，你就是在跟对方聊天，不是在给建议
- 走心：让对方感觉被理解、被在乎，而不是被说教

【严格遵守】
- 只输出一条消息，整段不换行（句号、逗号直接连着写）。例外：只在必须分两个意群、且不显啰嗦时，最多一个换行
- 按用户指定的回复风格写，风格的要求要渗透进每句话的语气和用词，而不是空喊风格名
- 结合对方说的话和情绪来回应，不要跑题、不要套话
- 可以适度补全语气和细节，但绝不编造事实、承诺、时间、地点、金额
- 避免 PUA、操控、冒犯、低俗、过度讨好、「爹味」说教
- 严禁输出任何前缀、编号、思考过程、引号、解释性文字
- 只输出可以直接点发送的回复正文，第一句话就要是给对方的回应

【反面例子，绝对不能这样写】
- 「第一条……\\n第二条……\\n第三条……」（拆成多条短消息，禁止）
- 「1 等我回复。 2 亲爱的……」（带编号/思考过程）
- 「需要我帮忙想想办法吗？我可以帮你……」（助手腔）
- 「面对这种情况，我们可以从以下几个因素来分析决策：」（说教/书面）
- 「我理解你现在的感受，每个人都会遇到这样的时候……」（鸡汤套话）
"""
}
