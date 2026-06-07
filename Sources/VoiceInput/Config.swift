import Foundation

// MARK: - 数据目录

/// 所有数据统一存放在 ~/.voice-input/
let appDataDir: String = NSHomeDirectory() + "/.voice-input"

/// 确保数据目录存在，返回目录路径
/// 首次运行时自动从 ~/voice-input-v2/ 迁移旧数据
func ensureAppDataDir() -> String {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: appDataDir, withIntermediateDirectories: true)

    // 一次性迁移旧目录数据
    let oldDir = NSHomeDirectory() + "/voice-input-v2"
    let marker = appDataDir + "/.migrated"
    if fm.fileExists(atPath: oldDir) && !fm.fileExists(atPath: marker) {
        for item in ["config.json", ".env", "transcriber.log", "streamer.log", "recordings"] {
            let src = oldDir + "/" + item
            let dst = appDataDir + "/" + item
            if fm.fileExists(atPath: src) && !fm.fileExists(atPath: dst) {
                try? fm.moveItem(atPath: src, toPath: dst)
            }
        }
        fm.createFile(atPath: marker, contents: nil)
    }

    // 一次性从 Library 旧目录迁移到 ~/.voice-input/
    let libraryDir = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
        .appending("/VoiceInput")
    let libMarker = appDataDir + "/.migrated-lib"
    if fm.fileExists(atPath: libraryDir) && !fm.fileExists(atPath: libMarker) {
        for item in ["config.json", ".env", "recordings", "models"] {
            let src = libraryDir + "/" + item
            let dst = appDataDir + "/" + item
            if fm.fileExists(atPath: src) && !fm.fileExists(atPath: dst) {
                try? fm.moveItem(atPath: src, toPath: dst)
            }
        }
        fm.createFile(atPath: libMarker, contents: nil)
        NSLog("[VI] 已从 \(libraryDir) 迁移到 \(appDataDir)")
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

    // 润色
    var polishEnabled: Bool = true
    var polishType: String = "cloud"             // cloud, local
    var polishApiUrl: String = "https://api.deepseek.com/chat/completions"
    var polishApiKey: String = ""
    var polishModel: String = "deepseek-v4-flash"

    // 通用
    var hotkey: String = "cmd_r"
    var saveRecordings: Bool = false
    var cjkSpacing: Bool = true                  // 中日韩字符与英文/数字之间加空格
    var soundEnabled: Bool = true                 // 录音开始/结束提示音
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

        polishEnabled = dict["polish_enabled"] != "false"
        polishType = dict["polish_type"] ?? "cloud"
        polishApiUrl = dict["polish_api_url"] ?? dict["deepseek_api_url"] ?? "https://api.deepseek.com/chat/completions"
        polishApiKey = env["POLISH_API_KEY"] ?? dict["polish_api_key"] ?? dict["deepseek_api_key"] ?? ""
        polishModel = dict["polish_model"] ?? dict["deepseek_model"] ?? "deepseek-v4-flash"

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
        let dict: [String: String] = [
            "asr_engine": asrEngine,
            "asr_provider": asrProvider,
            "asr_mode": asrMode,
            "local_model": localModel,
            "polish_enabled": polishEnabled ? "true" : "false",
            "polish_type": polishType,
            "polish_api_url": polishApiUrl,
            "polish_model": polishModel,
            "hotkey": hotkey,
            "save_recordings": saveRecordings ? "true" : "false",
            "cjk_spacing": cjkSpacing ? "true" : "false",
        ]
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
}
