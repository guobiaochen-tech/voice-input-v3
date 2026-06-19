import Foundation

// MARK: - 数据目录

/// 数据目录固定在 ~/.voice-input/（家目录点目录，与 Claude Code 等开发工具同路子，好找好编辑）
let appDataDir: String = {
    let env = ProcessInfo.processInfo.environment

    if let override = env["VOICE_INPUT_DATA_DIR"], !override.isEmpty {
        return (override as NSString).expandingTildeInPath
    }

    return NSHomeDirectory() + "/.voice-input"
}()

/// 确保数据目录存在，返回目录路径
/// 首次运行时自动从旧位置（项目目录 / ~/.voice-input / ~/voice-input-v2）迁移数据
func ensureAppDataDir() -> String {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: appDataDir, withIntermediateDirectories: true)

    // 迁移源按"新→旧"顺序：新数据先占位，旧数据只补缺（目标已存在则跳过，永不覆盖）。
    // 全部用 copy 保留源，避免迁移中途失败丢数据。
    let sources: [(path: String, marker: String)] = [
        (NSHomeDirectory() + "/Library/Application Support/VoiceInput", ".migrated-appsupport"),
        (NSHomeDirectory() + "/voice-input-v3/.voice-input", ".migrated-project"),
        (NSHomeDirectory() + "/voice-input-v2", ".migrated"),
    ]
    let items = ["config.json", ".env", "polish-prompt.md", "transcriber.log", "streamer.log", "recordings", "models", "prompts"]

    for (src, marker) in sources {
        let markerPath = appDataDir + "/" + marker
        guard src != appDataDir, fm.fileExists(atPath: src), !fm.fileExists(atPath: markerPath) else { continue }
        for item in items {
            let s = src + "/" + item
            let d = appDataDir + "/" + item
            if fm.fileExists(atPath: s) && !fm.fileExists(atPath: d) {
                try? fm.copyItem(atPath: s, toPath: d)
            }
        }
        fm.createFile(atPath: markerPath, contents: nil)
        NSLog("[VI] 已从 \(src) 复制数据到 \(appDataDir)")
    }

    // polish-prompt.md 统一挪进 prompts/ 子目录（所有提示词归一处）
    let oldPP = appDataDir + "/polish-prompt.md"
    let newPP = appDataDir + "/prompts/polish-prompt.md"
    if fm.fileExists(atPath: oldPP) && !fm.fileExists(atPath: newPP) {
        try? fm.createDirectory(atPath: appDataDir + "/prompts", withIntermediateDirectories: true)
        try? fm.moveItem(atPath: oldPP, toPath: newPP)
    }
    return appDataDir
}

// MARK: - 配置模型

struct AppConfig {
    // ASR
    var asrEngine: String = "third_party"       // apple_local, apple_cloud, third_party
    var asrProvider: String = ""                 // 第三方服务商名称
    var asrApiKey: String = ""
    var asrMode: String = "cloud"                // cloud, local
    var localModel: String = "sensevoice-small"  // 本地模型目录名

    // 润色模式：off 关闭 / polish 基本润色 / style 风格改写 / translate 翻译
    var polishMode: String = "polish"
    var polishType: String = "cloud"             // cloud, local（保留兼容，UI 不再显示）
    var polishApiUrl: String = "https://api.deepseek.com/chat/completions"
    var polishApiKey: String = ""
    var polishModel: String = "deepseek-v4-flash"
    var polishReplyStyle: String = "高情商"        // 风格 md 文件名（动态扫描 prompts/styles/）
    var translateLang: String = "英文"            // 翻译语言 md 文件名（动态扫描 prompts/translate/）

    // 通用
    var hotkey: String = "cmd_r"
    var saveRecordings: Bool = false
    var cjkSpacing: Bool = true                  // 中日韩字符与英文/数字之间加空格
    var soundEnabled: Bool = true                 // 录音开始/结束提示音

    // 服务商预设：用户下拉框选项 + 各自的 key（用户要求持久化 key）
    var llmPresets: [ProviderPreset] = ProviderPreset.defaultLLM
    var asrPresets: [AsrPreset] = AsrPreset.defaultASR
}

// MARK: - 服务商预设

/// LLM 服务商预设：存 name + api_url + model + key
/// 用户选预设自动填好前三项，key 每家单独保存，切换服务商不用重填。
/// 用户手填了预设之外的值，会作为新条目追加进数组（历史）。
struct ProviderPreset: Codable, Equatable {
    var name: String
    var apiUrl: String
    var model: String
    var apiKey: String
    var isBuiltin: Bool   // 内置预设（不可改名/删字段），区分用户历史条目

    static let defaultLLM: [ProviderPreset] = [
        ProviderPreset(name: "DeepSeek", apiUrl: "https://api.deepseek.com/chat/completions", model: "deepseek-chat", apiKey: "", isBuiltin: true),
        ProviderPreset(name: "Kimi (Moonshot)", apiUrl: "https://api.moonshot.cn/v1/chat/completions", model: "moonshot-v1-8k", apiKey: "", isBuiltin: true),
        ProviderPreset(name: "MiniMax", apiUrl: "https://api.minimax.io/v1/chat/completions", model: "MiniMax-Text-01", apiKey: "", isBuiltin: true),
        ProviderPreset(name: "MiMo (小米)", apiUrl: "", model: "MiMo-7B-RL", apiKey: "", isBuiltin: true),
        ProviderPreset(name: "Qwen (通义)", apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", model: "qwen-max", apiKey: "", isBuiltin: true),
        ProviderPreset(name: "火山 Doubao", apiUrl: "https://ark.cn-beijing.volces.com/api/v3/chat/completions", model: "doubao-pro-32k", apiKey: "", isBuiltin: true),
        ProviderPreset(name: "自定义", apiUrl: "", model: "", apiKey: "", isBuiltin: true),
    ]
}

/// 云端 ASR 服务商预设
struct AsrPreset: Codable, Equatable {
    var name: String
    var provider: String   // dashscope / tencent / xfyun
    var apiKey: String
    var implemented: Bool  // 是否已接入（false = 占位，后续版本更新）
    var isBuiltin: Bool

    static let defaultASR: [AsrPreset] = [
        AsrPreset(name: "阿里云 DashScope", provider: "dashscope", apiKey: "", implemented: true, isBuiltin: true),
        AsrPreset(name: "腾讯云 ASR", provider: "tencent", apiKey: "", implemented: false, isBuiltin: true),
        AsrPreset(name: "讯飞星火 ASR", provider: "xfyun", apiKey: "", implemented: false, isBuiltin: true),
    ]
}

// 兼容旧版字段名
extension AppConfig {

    /// 从系统环境变量和 .env 文件加载 API Key
    /// 优先级：系统环境变量 > .env 文件 > config.json
    private static func loadEnvVars() -> [String: String] {
        var env: [String: String] = [:]

        // 1. .env 文件
        let envPath = ensureAppDataDir() + "/.env"
        if let content = try? String(contentsOfFile: envPath) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                if let eqRange = trimmed.range(of: "=") {
                    let key = String(trimmed[trimmed.startIndex..<eqRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    let value = String(trimmed[eqRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    if (key == "ASR_API_KEY" || key == "POLISH_API_KEY") && !value.isEmpty {
                        env[key] = value
                    }
                }
            }
        }

        // 2. 系统环境变量覆盖 .env
        let sysEnv = ProcessInfo.processInfo.environment
        for key in ["ASR_API_KEY", "POLISH_API_KEY"] {
            if let value = sysEnv[key] ?? sysEnv["VOICE_INPUT_\(key)"], !value.isEmpty {
                env[key] = value
            }
        }

        return env
    }

    init(fromDict dict: [String: String]) {
        let env = Self.loadEnvVars()

        asrEngine = dict["asr_engine"] ?? "third_party"
        asrProvider = dict["asr_provider"] ?? ""
        asrApiKey = env["ASR_API_KEY"] ?? dict["asr_api_key"] ?? dict["dashscope_api_key"] ?? ""
        asrMode = dict["asr_mode"] ?? "cloud"
        localModel = dict["local_model"] ?? "sensevoice-small"

        // polish_mode 迁移：旧配置只有 polish_enabled 布尔；style 模式已废弃，降级为润色
        if let mode = dict["polish_mode"], !mode.isEmpty {
            polishMode = mode == "style" ? "polish" : mode
        } else {
            polishMode = dict["polish_enabled"] == "false" ? "off" : "polish"
        }
        polishType = dict["polish_type"] ?? "cloud"
        polishApiUrl = dict["polish_api_url"] ?? dict["deepseek_api_url"] ?? "https://api.deepseek.com/chat/completions"
        polishApiKey = env["POLISH_API_KEY"] ?? dict["polish_api_key"] ?? dict["deepseek_api_key"] ?? ""
        polishModel = dict["polish_model"] ?? dict["deepseek_model"] ?? "deepseek-v4-flash"
        polishReplyStyle = dict["polish_reply_style"] ?? "高情商"
        translateLang = dict["translate_lang"] ?? "英文"

        // 预设列表：缺失时用内置默认；存在时解码（保留用户的历史条目和 key）
        if let data = dict["llm_presets"]?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ProviderPreset].self, from: data) {
            // 合并：以内置默认为骨架，用磁盘里的 key/历史覆盖
            llmPresets = Self.mergeLLMPresets(saved: decoded)
        }
        if let data = dict["asr_presets"]?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([AsrPreset].self, from: data) {
            asrPresets = Self.mergeASRPresets(saved: decoded)
        }

        hotkey = dict["hotkey"] ?? "cmd_r"
        saveRecordings = dict["save_recordings"] == "true"
        cjkSpacing = dict["cjk_spacing"] != "false" // 默认 true，只有 "false" 才关闭
    }
}

// MARK: - 快捷键映射

/// macOS 虚拟键码 → (配置名, 显示名)
let KEYCODE_MAP: [UInt16: (configName: String, displayName: String)] = [
    // F 键
    122: ("f1",  "F1"),   120: ("f2",  "F2"),   99:  ("f3",  "F3"),
    118: ("f4",  "F4"),   96:  ("f5",  "F5"),   97:  ("f6",  "F6"),
    98:  ("f7",  "F7"),   100: ("f8",  "F8"),   101: ("f9",  "F9"),
    109: ("f10", "F10"),  103: ("f11", "F11"),  111: ("f12", "F12"),
    // 修饰键
    56:  ("shift_l", "左 Shift"),   60: ("shift_r", "右 Shift"),
    59:  ("ctrl_l",  "左 Ctrl"),    62: ("ctrl_r",  "右 Ctrl"),
    58:  ("alt_l",   "左 Option"),  61: ("alt_r",   "右 Option"),
    55:  ("cmd_l",   "左 Command"), 54: ("cmd_r",   "右 Command"),
    63:  ("fn",      "Fn"),
    // 其他键
    49:  ("space",  "空格"),
    126: ("up",     "↑"),   125: ("down",  "↓"),
    123: ("left",   "←"),   124: ("right", "→"),
    51:  ("delete", "Delete"),
    48:  ("tab",    "Tab"),
    36:  ("return", "Return"),
    // 字母键
    0:   ("a", "A"),  1:   ("s", "S"),  2:   ("d", "D"),  3:   ("f", "F"),
    4:   ("h", "H"),  5:   ("g", "G"),  6:   ("z", "Z"),  7:   ("x", "X"),
    8:   ("c", "C"),  9:   ("v", "V"),  11:  ("b", "B"),  12:  ("q", "Q"),
    13:  ("w", "W"),  14:  ("e", "E"),  15:  ("r", "R"),  16:  ("y", "Y"),
    17:  ("t", "T"),  31:  ("o", "O"),  32:  ("u", "U"),  34:  ("i", "I"),
    35:  ("p", "P"),  37:  ("l", "L"),  38:  ("j", "J"),  40:  ("k", "K"),
    45:  ("n", "N"),  46:  ("m", "M"),
    // 数字键
    18:  ("1", "1"),  19:  ("2", "2"),  20:  ("3", "3"),  21:  ("4", "4"),
    23:  ("5", "5"),  22:  ("6", "6"),  26:  ("7", "7"),  28:  ("8", "8"),
    25:  ("9", "9"),  29:  ("0", "0"),
]

/// 配置名 → 显示名
let HOTKEY_DISPLAY: [String: String] = {
    var map = [String: String]()
    for (_, value) in KEYCODE_MAP { map[value.configName] = value.displayName }
    return map
}()

/// 配置名 → macOS 键码
let HOTKEY_KEYCODE: [String: UInt16] = {
    var map = [String: UInt16]()
    for (keycode, value) in KEYCODE_MAP { map[value.configName] = keycode }
    return map
}()

/// 快捷键冲突提示
let KEY_CONFLICTS: [String: String] = [
    "f2":    "MacBook 默认调亮度",
    "f3":    "MacBook 默认 Mission Control",
    "f4":    "MacBook 默认 Spotlight",
    "f5":    "MacBook 默认调亮度",
    "f6":    "MacBook 默认调键盘灯",
    "f7":    "MacBook 默认媒体后退",
    "f8":    "MacBook 默认播放/暂停",
    "f9":    "MacBook 默认媒体前进",
    "f10":   "MacBook 默认静音",
    "f11":   "MacBook 默认音量-",
    "f12":   "MacBook 默认音量+",
    "cmd_l": "会和大量快捷键冲突",
    "ctrl_l": "会和部分快捷键冲突",
    "shift_l": "会和输入法冲突",
]

// MARK: - 配置读写

class ConfigManager {
    static let shared = ConfigManager()

    let configPath: String
    var config: AppConfig

    init() {
        configPath = ensureAppDataDir() + "/config.json"
        config = Self.load(from: configPath)
    }

    private static func load(from path: String) -> AppConfig {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            let cfg = AppConfig()
            cfg.save(to: path)
            return cfg
        }
        let cfg = AppConfig(fromDict: dict)
        cfg.save(to: path)
        return cfg
    }

    func save() {
        config.save(to: configPath)
    }
}

extension AppConfig {
    func save(to path: String) {
        // config.json 不存 API Key，只存非敏感配置
        var dict: [String: String] = [
            "asr_engine": asrEngine,
            "asr_provider": asrProvider,
            "asr_mode": asrMode,
            "local_model": localModel,
            "polish_mode": polishMode,
            "polish_type": polishType,
            "polish_api_url": polishApiUrl,
            "polish_model": polishModel,
            "polish_reply_style": polishReplyStyle,
            "translate_lang": translateLang,
            "hotkey": hotkey,
            "save_recordings": saveRecordings ? "true" : "false",
            "cjk_spacing": cjkSpacing ? "true" : "false",
        ]
        // 预设列表单独编码成 JSON 字符串
        if let llmData = try? JSONEncoder().encode(llmPresets),
           let llmStr = String(data: llmData, encoding: .utf8) {
            dict["llm_presets"] = llmStr
        }
        if let asrData = try? JSONEncoder().encode(asrPresets),
           let asrStr = String(data: asrData, encoding: .utf8) {
            dict["asr_presets"] = asrStr
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path))
    }

    /// API Key 保存到 .env 文件，不进 config.json
    static func saveEnv(asrApiKey: String, polishApiKey: String, to dir: String) {
        let envPath = dir + "/.env"
        var lines: [String] = []

        // 读取现有 .env，保留非 key 行和注释
        if let content = try? String(contentsOfFile: envPath) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("ASR_API_KEY=") && !trimmed.hasPrefix("POLISH_API_KEY=") {
                    lines.append(line)
                }
            }
        }

        lines.append("ASR_API_KEY=\(asrApiKey)")
        lines.append("POLISH_API_KEY=\(polishApiKey)")

        try? lines.joined(separator: "\n").write(toFile: envPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envPath)
    }

    /// 合并 LLM 预设：以当前内置默认为骨架，把磁盘里同名的 key/url/model 覆盖回去，
    /// 再追加磁盘里的非内置历史条目。这样内置预设新增项能跟上版本，用户的 key 不丢。
    private static func mergeLLMPresets(saved: [ProviderPreset]) -> [ProviderPreset] {
        var result = ProviderPreset.defaultLLM
        for i in result.indices {
            if let s = saved.first(where: { $0.name == result[i].name && $0.isBuiltin }) {
                result[i].apiUrl = s.apiUrl.isEmpty ? result[i].apiUrl : s.apiUrl
                result[i].model = s.model.isEmpty ? result[i].model : s.model
                result[i].apiKey = s.apiKey
            }
        }
        // 用户自建历史条目
        result.append(contentsOf: saved.filter { !$0.isBuiltin })
        return result
    }

    private static func mergeASRPresets(saved: [AsrPreset]) -> [AsrPreset] {
        var result = AsrPreset.defaultASR
        for i in result.indices {
            if let s = saved.first(where: { $0.provider == result[i].provider && $0.isBuiltin }) {
                result[i].apiKey = s.apiKey
            }
        }
        return result
    }
}
