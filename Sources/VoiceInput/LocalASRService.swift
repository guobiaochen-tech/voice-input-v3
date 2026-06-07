import Foundation

// MARK: - Character 扩展：CJK 字符判断

extension Character {
    var isCJKCharacter: Bool {
        let scalars = unicodeScalars
        guard let first = scalars.first else { return false }
        let v = first.value
        return (0x4E00...0x9FFF).contains(v)   // CJK Unified
            || (0x3040...0x309F).contains(v)   // Hiragana
            || (0x30A0...0x30FF).contains(v)   // Katakana
            || (0xAC00...0xD7AF).contains(v)   // Hangul
            || (0x3400...0x4DBF).contains(v)   // CJK Extension A
            || (0x20000...0x2A6DF).contains(v) // CJK Extension B
            || (0xF900...0xFAFF).contains(v)   // CJK Compat
    }
}

/// 本地语音识别服务 - 使用 sherpa-onnx
/// 支持 SenseVoice / Paraformer / Whisper 三种模型类型
/// 参考 Typeoff 的 LocalASRService.js 实现数据处理流程
///
/// SPM 编译时（swift build）此类方法返回空/抛错
/// 正式编译由 build.sh 通过 swiftc 链接 sherpa-onnx
class LocalASRService {
    static let shared = LocalASRService()

    #if SHERPA_ONNX
    private var recognizer: SherpaOnnxOfflineRecognizer?
    #endif

    private(set) var isLoaded = false
    private let queue = DispatchQueue(label: "com.paul.voiceinput.localasr")

    // 云端模式下空闲 5 分钟自动卸载模型
    private var autoUnloadTimer: Timer?
    private let autoUnloadInterval: TimeInterval = 5 * 60

    private init() {}

    // MARK: - 模型加载

    /// 根据当前选择的模型类型加载到内存
    func loadModel() throws {
        #if SHERPA_ONNX
        guard !isLoaded else { return }

        let modelId: String = MainActor.assumeIsolated {
            AppState.shared.localModel
        }
        let modelsRoot = ensureAppDataDir() + "/models"
        let modelDir = modelsRoot + "/" + modelId
        let tokensPath = modelDir + "/tokens.txt"

        let fm = FileManager.default
        guard fm.fileExists(atPath: tokensPath) else {
            throw LocalASRError.modelNotDownloaded
        }

        NSLog("[VI-LASR] 加载模型: \(modelId)")

        // 先构建基础模型配置，再根据模型类型填充对应字段
        var modelConfig = sherpaOnnxOfflineModelConfig(
            tokens: tokensPath,
            numThreads: 2,
            provider: "coreml",
            debug: 0
        )

        if modelId.hasPrefix("whisper") {
            // Whisper 系列：encoder + decoder + tokens
            let encoderPath = modelDir + "/encoder.onnx"
            let decoderPath = modelDir + "/decoder.onnx"
            guard fm.fileExists(atPath: encoderPath), fm.fileExists(atPath: decoderPath) else {
                throw LocalASRError.modelNotDownloaded
            }
            modelConfig.whisper = sherpaOnnxOfflineWhisperModelConfig(
                encoder: encoderPath,
                decoder: decoderPath,
                language: "",
                task: "transcribe"
            )
        } else if modelId.hasPrefix("paraformer") {
            // Paraformer：model + tokens
            let modelPath = modelDir + "/model.onnx"
            guard fm.fileExists(atPath: modelPath) else {
                throw LocalASRError.modelNotDownloaded
            }
            modelConfig.paraformer = sherpaOnnxOfflineParaformerModelConfig(model: modelPath)
        } else {
            // SenseVoice 及其他：model + tokens
            let modelPath = modelDir + "/model.onnx"
            guard fm.fileExists(atPath: modelPath) else {
                throw LocalASRError.modelNotDownloaded
            }
            modelConfig.sense_voice = sherpaOnnxOfflineSenseVoiceModelConfig(
                model: modelPath,
                language: "",
                useInverseTextNormalization: true
            )
        }

        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: 16000,
            featureDim: 80
        )

        var config = sherpaOnnxOfflineRecognizerConfig(
            featConfig: featConfig,
            modelConfig: modelConfig
        )

        let startTime = Date()
        recognizer = SherpaOnnxOfflineRecognizer(config: &config)
        let loadTime = Date().timeIntervalSince(startTime) * 1000

        isLoaded = true
        NSLog("[VI-LASR] 模型加载完成 (\(Int(loadTime))ms)")
        #else
        NSLog("[VI-LASR] sherpa-onnx 未链接，无法加载模型")
        throw LocalASRError.notLoaded
        #endif
    }

    /// 卸载模型，释放内存
    func unloadModel() {
        cancelAutoUnload()
        guard isLoaded else { return }
        #if SHERPA_ONNX
        recognizer = nil
        #endif
        isLoaded = false
        NSLog("[VI-LASR] 模型已卸载")
    }

    // MARK: - 性能测试

    /// 测试指定模型的加载和推理速度
    /// 返回 "加载Xms 推理Xms" 或 nil（失败）
    func benchmark(id: String) -> String? {
        #if SHERPA_ONNX
        // 保存当前状态
        let previousModel = MainActor.assumeIsolated { AppState.shared.localModel }
        let wasLoaded = isLoaded

        // 切换到目标模型
        MainActor.assumeIsolated { AppState.shared.localModel = id }

        defer {
            // 恢复
            unloadModel()
            MainActor.assumeIsolated { AppState.shared.localModel = previousModel }
        }

        do {
            // 测加载
            let loadStart = Date()
            try loadModel()
            let loadMs = Int(Date().timeIntervalSince(loadStart) * 1000)

            // 生成 2 秒低电平噪声作为测试音频
            let sampleCount = 16000 * 2
            var samples = [Float](repeating: 0, count: sampleCount)
            for i in 0..<sampleCount {
                samples[i] = Float.random(in: -0.01...0.01)
            }

            // 测推理
            let inferStart = Date()
            let _ = try transcribe(samples: samples)
            let inferMs = Int(Date().timeIntervalSince(inferStart) * 1000)

            NSLog("[VI-LASR] benchmark \(id): 加载\(loadMs)ms 推理\(inferMs)ms")
            return "加载\(loadMs)ms 推理\(inferMs)ms"
        } catch {
            NSLog("[VI-LASR] benchmark \(id) 失败: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - 识别

    /// 转录 Float32 音频数据
    /// 数据处理流程和 Typeoff 一模一样：
    /// 1. 接收 16kHz 单声道 Float32 采样
    /// 2. 超过 28 秒按 28 秒分段
    /// 3. 每段独立推理
    /// 4. 拼接结果 + 后处理
    func transcribe(samples: [Float]) throws -> String {
        guard !samples.isEmpty else { return "" }

        #if SHERPA_ONNX
        // 确保模型已加载
        if !isLoaded {
            try loadModel()
        }

        guard let rec = recognizer else {
            throw LocalASRError.notLoaded
        }

        let startTime = Date()
        let sampleRate = 16000
        let maxChunkSeconds = 28
        let maxChunkSamples = sampleRate * maxChunkSeconds
        let totalSamples = samples.count
        var textParts: [String] = []

        if totalSamples <= maxChunkSamples {
            let result = rec.decode(samples: samples, sampleRate: sampleRate)
            textParts.append(result.text)
        } else {
            let totalChunks = (totalSamples + maxChunkSamples - 1) / maxChunkSamples
            NSLog("[VI-LASR] 长音频分段: \(totalChunks) 段 (\(maxChunkSeconds)s/段)")

            var start = 0
            var chunkIndex = 0
            while start < totalSamples {
                let end = min(start + maxChunkSamples, totalSamples)
                let chunkSamples = Array(samples[start..<end])

                let result = rec.decode(samples: chunkSamples, sampleRate: sampleRate)
                textParts.append(result.text)

                chunkIndex += 1
                let chunkDuration = Float(end - start) / Float(sampleRate)
                NSLog("[VI-LASR] 分段 \(chunkIndex)/\(totalChunks): \(String(format: "%.1f", chunkDuration))s, \(result.text.count) 字")

                start = end
            }
        }

        // 分段拼接：中文直接拼，英文/中英边界加空格防粘词
        var fullText = ""
        for (i, part) in textParts.enumerated() {
            if i > 0 && !fullText.isEmpty && !part.isEmpty {
                let lastChar = fullText[fullText.index(before: fullText.endIndex)]
                let firstChar = part[part.startIndex]
                // 两端都是字母/数字时加空格
                if lastChar.isLetter && firstChar.isLetter {
                    // 但如果都是 CJK 字符，不加空格
                    let lastCJK = lastChar.isCJKCharacter
                    let firstCJK = firstChar.isCJKCharacter
                    if !lastCJK || !firstCJK {
                        fullText += " "
                    }
                }
            }
            fullText += part
        }
        let transcribeTime = Date().timeIntervalSince(startTime) * 1000
        let audioDuration = Float(samples.count) / Float(sampleRate)

        let cleanedText = postProcess(fullText)

        NSLog("[VI-LASR] 识别完成: \(Int(transcribeTime))ms, 音频 \(String(format: "%.1f", audioDuration))s, \(cleanedText.count) 字")

        scheduleAutoUnloadIfNeeded()

        return cleanedText
        #else
        NSLog("[VI-LASR] sherpa-onnx 未链接")
        throw LocalASRError.notLoaded
        #endif
    }

    // MARK: - 后处理（和 Typeoff 一模一样）

    /// 1. 清理 SenseVoice 特殊标签
    /// 2. 单行文本去末尾句号
    /// 3. CJK 空格处理
    private func postProcess(_ text: String) -> String {
        var result = text

        // 1. 清理 SenseVoice 标签：如 <|zh|><|NEUTRAL|><|Speech|><|woitn|>
        if let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. 单行文本：去掉末尾句号
        if !result.contains("\n") {
            if let regex = try? NSRegularExpression(pattern: "[.。।॥။។።։།]$", options: []) {
                let range = NSRange(result.startIndex..., in: result)
                if let match = regex.firstMatch(in: result, options: [], range: range) {
                    result = String(result[..<result.index(result.startIndex, offsetBy: match.range.lowerBound)])
                }
            }
        }

        // 3. CJK 空格
        let cfg = ConfigManager.shared.config
        if cfg.cjkSpacing {
            result = addCJKSpacing(result)
        }

        return result
    }

    private func addCJKSpacing(_ text: String) -> String {
        let cjk = "[\\u{4e00}-\\u{9fff}\\u{3040}-\\u{309f}\\u{30a0}-\\u{30ff}\\u{ac00}-\\u{d7af}]"
        let alphaNum = "[A-Za-z0-9]"

        var result = text

        if let re1 = try? NSRegularExpression(pattern: "(\(cjk))(\(alphaNum))", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = re1.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }

        if let re2 = try? NSRegularExpression(pattern: "(\(alphaNum))(\(cjk))", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = re2.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2")
        }

        return result
    }

    // MARK: - 自动卸载

    private func scheduleAutoUnloadIfNeeded() {
        cancelAutoUnload()
        let cfg = ConfigManager.shared.config
        guard cfg.asrMode == "cloud" else { return }

        autoUnloadTimer = Timer.scheduledTimer(withTimeInterval: autoUnloadInterval, repeats: false) { [weak self] _ in
            if self?.isLoaded == true {
                NSLog("[VI-LASR] 空闲自动卸载模型")
                self?.unloadModel()
            }
        }
    }

    private func cancelAutoUnload() {
        autoUnloadTimer?.invalidate()
        autoUnloadTimer = nil
    }

    // MARK: - 错误

    enum LocalASRError: LocalizedError {
        case notLoaded
        case modelNotDownloaded

        var errorDescription: String? {
            switch self {
            case .notLoaded: "本地识别模型未加载"
            case .modelNotDownloaded: "本地识别模型未下载"
            }
        }
    }
}
