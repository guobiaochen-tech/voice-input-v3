import SwiftUI
import ServiceManagement
import AVFoundation

@MainActor
@Observable
class AppState {
    static let shared = AppState()

    // ASR
    var asrEngine = "third_party"
    var asrProvider = ""
    var asrApiKey = ""
    var asrMode = "cloud"   // cloud, local
    var localModel = "sensevoice-small"

    // 润色模式：off 关闭 / polish 基本润色 / style 风格改写 / translate 翻译
    var polishMode = "polish"
    var polishType = "cloud"
    var polishApiUrl = "https://api.deepseek.com/chat/completions"
    var polishApiKey = ""
    var polishModel = "deepseek-v4-flash"
    var polishReplyStyle = "高情商"
    var translateLang = "英文"

    // 通用
    var hotkey = "cmd_r"
    var launchAtLogin = false
    var saveRecordings = false
    var cjkSpacing = true
    var soundEnabled = true

    // 服务商预设（含 key，用户要求持久化）
    var llmPresets: [ProviderPreset] = ProviderPreset.defaultLLM
    var asrPresets: [AsrPreset] = AsrPreset.defaultASR

    var isRecording = false
    var isProcessing = false
    var isReady = false
    var statusText = "启动中..."

    let hotkeyManager = HotkeyManager()
    let audioRecorder = AudioRecorder()
    let transcriber = Transcriber()  // 云端 DashScope

    private init() {
        loadConfig()
        PromptManager.ensureDefaults()
    }

    private func loadConfig() {
        let cfg = ConfigManager.shared.config
        asrEngine = cfg.asrEngine
        asrProvider = cfg.asrProvider
        asrApiKey = cfg.asrApiKey
        asrMode = cfg.asrMode
        localModel = cfg.localModel
        polishMode = cfg.polishMode
        polishType = cfg.polishType
        polishApiUrl = cfg.polishApiUrl
        polishApiKey = cfg.polishApiKey
        polishModel = cfg.polishModel
        polishReplyStyle = cfg.polishReplyStyle
        translateLang = cfg.translateLang
        hotkey = cfg.hotkey
        saveRecordings = cfg.saveRecordings
        cjkSpacing = cfg.cjkSpacing
        soundEnabled = cfg.soundEnabled
        llmPresets = cfg.llmPresets
        asrPresets = cfg.asrPresets
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setup() {
        NSLog("[VI] setup()")
        checkAccessibilityPermission()
        requestMicrophonePermission()
        setupHotkey()
        initRecognizer()
    }

    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            NSLog("[VI] 麦克风权限: 已授权")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                NSLog("[VI] 麦克风权限: \(granted ? "用户已允许" : "用户已拒绝")")
                if !granted {
                    Task { @MainActor in
                        ClipboardHelper.notify(title: "语音输入", message: "需要麦克风权限才能录音，请在系统设置中开启")
                    }
                }
            }
        case .denied, .restricted:
            NSLog("[VI] 麦克风权限: 未授权")
            ClipboardHelper.notify(title: "语音输入", message: "需要麦克风权限才能录音，请在系统设置 → 隐私与安全性 → 麦克风 中开启")
        @unknown default:
            NSLog("[VI] 麦克风权限: 未知状态")
        }
    }

    /// 检查麦克风权限。未授权则弹窗请求。
    /// .notDetermined 时触发弹窗并返回 false（等用户点完再试）
    /// .denied 时通知用户去设置里开
    private func ensureMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            // 触发系统弹窗，返回 false 让用户再按一次
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                NSLog("[VI] 麦克风权限: \(granted ? "用户已允许" : "用户已拒绝")")
            }
            statusText = "请允许麦克风权限后重试"
            return false
        case .denied, .restricted:
            ClipboardHelper.notify(title: "语音输入", message: "需要麦克风权限，请在系统设置 → 隐私与安全性 → 麦克风 中开启")
            statusText = "需要麦克风权限"
            return false
        @unknown default:
            return false
        }
    }

    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        NSLog("[VI] 辅助功能权限: \(trusted ? "已开启" : "未开启")")
        if !trusted {
            statusText = "需要辅助功能权限"
            ClipboardHelper.notify(title: "语音输入", message: "请在系统设置 -> 隐私与安全性 -> 辅助功能 中开启")
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as NSDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    private func setupHotkey() {
        guard let keycode = HOTKEY_KEYCODE[hotkey] else {
            NSLog("[VI] 未知快捷键: \(hotkey)")
            return
        }
        hotkeyManager.updateHotkey(hotkey)
        hotkeyManager.onPress = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkeyManager.onRelease = { [weak self] in
            Task { @MainActor in self?.stopRecordingAndProcess() }
        }
        hotkeyManager.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelRecording() }
        }
        hotkeyManager.start()
        NSLog("[VI] 快捷键: \(hotkey)")
    }

    func reinitRecognizer() {
        isReady = false
        LocalASRService.shared.unloadModel()
        transcriber.reset()
        initRecognizer()
    }

    private func initRecognizer() {
        // 云端模式没 API Key 时，自动切到本地模式
        if asrMode == "cloud" && asrApiKey.isEmpty {
            NSLog("[VI] 云端模式但无 API Key，自动切到本地模式")
            asrMode = "local"
        }

        switch asrMode {
        case "cloud":
            // 云端模式：初始化 DashScope WebSocket
            transcriber.setApiKey(asrApiKey)
            transcriber.setPartialResultCallback { text in
                Task { @MainActor in
                    FloatingOverlay.shared.updatePartialText(text)
                }
            }
            isReady = true
            statusText = "就绪"
            NSLog("[VI] 就绪 (云端模式)")

        case "local":
            // 本地模式：不需要 API Key
            isReady = true
            statusText = "就绪"
            NSLog("[VI] 就绪 (本地模式)")

        default:
            statusText = "未知 ASR 模式"
            NSLog("[VI] 未知 ASR 模式: \(asrMode)")
        }
    }

    // MARK: - 录音

    func startRecording() {
        guard !isRecording, !isProcessing, isReady else {
            NSLog("[VI] startRecording 跳过: recording=\(isRecording) processing=\(isProcessing) ready=\(isReady)")
            return
        }

        // 录音前检查麦克风权限，未授权则弹窗请求
        guard ensureMicrophonePermission() else {
            NSLog("[VI] 麦克风权限未授予")
            return
        }

        // 提示音：开始
        if soundEnabled { NSSound(named: "Tink")?.play() }

        isRecording = true

        FloatingOverlay.shared.show(state: .recording)

        // 音量回调（兼容）
        audioRecorder.onVolume = { level in
            Task { @MainActor in
                FloatingOverlay.shared.updateVolume(level)
            }
        }

        // 频谱回调（真正的 FFT 频谱）
        audioRecorder.onSpectrum = { bands in
            Task { @MainActor in
                FloatingOverlay.shared.updateSpectrum(bands)
            }
        }

        // 云端模式：实时流式
        if asrMode == "cloud" {
            do {
                try transcriber.startLiveRecognition()
                audioRecorder.onBuffer = { [weak self] buffer in
                    guard let self = self else { return }
                    self.transcriber.appendBuffer(buffer)
                }
            } catch {
                NSLog("[VI] 云端连接失败: \(error)")
                // 云端连接失败，如果有本地模型，切到本地
                if ModelManager.shared.isModelDownloaded() {
                    NSLog("[VI] 自动切换到本地模式")
                    asrMode = "local"
                } else {
                    isRecording = false
                    FloatingOverlay.shared.hide()
                    statusText = "连接失败"
                    return
                }
            }
        }

        // 本地模式：只录音，不流式
        if asrMode == "local" {
            audioRecorder.onBuffer = nil
        }

        // 计时器
        startTimer()

        do {
            try audioRecorder.start()
            NSLog("[VI] 录音已启动 (\(asrMode) 模式)")
        } catch {
            NSLog("[VI] 录音启动失败: \(error)")
            isRecording = false
            recordingTimer?.invalidate()
            recordingTimer = nil
            FloatingOverlay.shared.hide()
            statusText = "录音启动失败"
        }
    }

    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private let maxRecordingDuration: TimeInterval = 120

    private func startTimer() {
        recordingStartTime = Date()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartTime else { return }
                let duration = Date().timeIntervalSince(start)
                FloatingOverlay.shared.updateDuration(duration)

                if duration >= self.maxRecordingDuration, self.isRecording {
                    NSLog("[VI] 达到最长录音时长 \(Int(self.maxRecordingDuration)) 秒，自动结束录音")
                    self.statusText = "达到最长录音时长，处理中..."
                    self.stopRecordingAndProcess()
                }
            }
        }
    }

    /// 将临时 WAV 文件保存到录音目录
    private func saveRecordingFile(_ wavUrl: URL) {
        let recordingsDir = ensureAppDataDir() + "/recordings"
        try? FileManager.default.createDirectory(atPath: recordingsDir, withIntermediateDirectories: true)
        let destPath = recordingsDir + "/recording_\(Int(Date().timeIntervalSince1970)).wav"
        do {
            try FileManager.default.moveItem(atPath: wavUrl.path, toPath: destPath)
            NSLog("[VI] 录音已保存: \(destPath)")
        } catch {
            // move 失败（跨分区等）尝试 copy
            try? FileManager.default.copyItem(atPath: wavUrl.path, toPath: destPath)
            try? FileManager.default.removeItem(at: wavUrl)
            NSLog("[VI] 录音已保存(copy): \(destPath)")
        }
    }

    func stopRecordingAndProcess() {
        guard isRecording else { return }

        // 提示音：结束
        if soundEnabled { NSSound(named: "Tink")?.play() }
        isRecording = false
        isProcessing = true
        audioRecorder.onBuffer = nil
        audioRecorder.onVolume = nil
        audioRecorder.onSpectrum = nil
        recordingTimer?.invalidate()
        recordingTimer = nil

        // 一次性停止录音并取出音频数据，后续云端/本地/fallback 都用这份数据
        let (audioSamples, wavUrl) = audioRecorder.stopAndGetResults(saveWav: saveRecordings)

        // 保存录音到指定目录
        if saveRecordings, let wavUrl = wavUrl {
            saveRecordingFile(wavUrl)
        }

        // 切到思考状态
        FloatingOverlay.shared.show(state: .thinking)

        Task {
            var resultText: String?

            if asrMode == "cloud" {
                resultText = await processCloud()
                // 云端失败，尝试本地 fallback（用提前取出的音频数据）
                if (resultText ?? "").isEmpty && ModelManager.shared.isModelDownloaded() {
                    NSLog("[VI] 云端失败，回退到本地")
                    resultText = await processLocal(samples: audioSamples)
                }
            } else {
                resultText = await processLocal(samples: audioSamples)
                // 本地失败，尝试云端 fallback
                if (resultText ?? "").isEmpty && !asrApiKey.isEmpty {
                    NSLog("[VI] 本地失败，回退到云端")
                    resultText = await processCloud()
                }
            }

            guard isProcessing else {
                NSLog("[VI] 已被取消，跳过输出")
                return
            }

            guard var text = resultText, !text.isEmpty else {
                NSLog("[VI] 未识别到内容")
                statusText = "未识别到内容"
                FloatingOverlay.shared.hide()
                isProcessing = false
                return
            }

            NSLog("[VI] 识别结果: \(text.prefix(50))")

            // 第一步：先润色/翻译（清口水词、纠同音错字），让后续命令词判断更准。
            // polishMode: off 原样 / polish 润色 / translate 翻译
            switch polishMode {
            case "polish":
                do {
                    let polished = try await TextPolisher().polish(
                        text: text, apiKey: polishApiKey,
                        model: polishModel, apiUrl: polishApiUrl
                    )
                    NSLog("[VI] 润色结果: \(polished.prefix(50))")
                    text = polished
                } catch {
                    NSLog("[VI] 润色失败，使用原始文本: \(error)")
                }
            case "translate":
                do {
                    let translated = try await TextPolisher().translate(
                        text: text, lang: translateLang,
                        apiKey: polishApiKey, model: polishModel, apiUrl: polishApiUrl
                    )
                    NSLog("[VI] 翻译结果: \(translated.prefix(50))")
                    text = translated
                } catch {
                    NSLog("[VI] 翻译失败，使用原始文本: \(error)")
                }
            default:
                break // off：原样
            }

            // 第二步：润色后再判断是不是「帮我回复」命令
            switch VoiceCommandParser.parse(text) {
            case .normal:
                break // 普通文本，直接用（已润色）的 text
            case .reply(let intent):
                text = (try? await regenerateReply(intent: intent)) ?? text
            }

            guard isProcessing else {
                NSLog("[VI] 已被取消，跳过输出")
                return
            }

            // 隐藏指示器
            FloatingOverlay.shared.hide()

            // 等待指示器隐藏，让焦点回到目标应用
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

            // 剪贴板粘贴
            do {
                try TextInputService.pasteText(text)
                NSLog("[VI] 文本已粘贴")
            } catch {
                NSLog("[VI] 粘贴失败: \(error)")
            }

            isProcessing = false
            statusText = "就绪"
        }
    }

    // MARK: - 云端处理

    private func processCloud() async -> String? {
        // 录音已在上层停止，只需停止流式识别获取最终结果
        let finalText = await transcriber.stopLiveRecognition()
        return finalText
    }

    // MARK: - 本地处理

    private func processLocal(samples: [Float]) async -> String? {
        guard !samples.isEmpty else {
            NSLog("[VI] 本地识别：无音频数据")
            return nil
        }

        do {
            if !LocalASRService.shared.isLoaded {
                try LocalASRService.shared.loadModel()
            }
            let text = try LocalASRService.shared.transcribe(samples: samples)
            return text.isEmpty ? nil : text
        } catch {
            NSLog("[VI] 本地识别失败: \(error)")
            return nil
        }
    }

    // MARK: - 帮我回复

    /// 复制当前选区作为聊天上下文，调 LLM 生成真人风格回复。
    /// 选区空则回退用剪贴板里的内容。失败返回 nil（上层走兜底）。
    private func regenerateReply(intent: String) async throws -> String {
        // 复制当前选中的对方发言（选区空则用剪贴板）
        let context = (try? TextInputService.copySelectedText()) ?? ""
        NSLog("[VI] 回复上下文: \(context.prefix(50))")

        let reply = try await TextPolisher().composeReply(
            context: context,
            intent: intent,
            style: polishReplyStyle,
            apiKey: polishApiKey,
            model: polishModel,
            apiUrl: polishApiUrl
        )
        NSLog("[VI] 回复结果: \(reply.prefix(50))")
        return reply
    }

    // MARK: - 取消

    func cancelRecording() {
        if isRecording {
            isRecording = false
            audioRecorder.onBuffer = nil
            audioRecorder.onVolume = nil
            recordingTimer?.invalidate()
            recordingTimer = nil
            _ = audioRecorder.stop()
            transcriber.reset()
        } else if isProcessing {
            isProcessing = false
            transcriber.reset()
        } else {
            return
        }
        FloatingOverlay.shared.hide()
        NSLog("[VI] 已取消")
        statusText = "就绪"
    }

    // MARK: - 保存配置

    func saveConfig() {
        var cfg = ConfigManager.shared.config
        cfg.asrEngine = asrEngine
        cfg.asrProvider = asrProvider
        cfg.asrApiKey = asrApiKey
        cfg.asrMode = asrMode
        cfg.localModel = localModel
        cfg.polishMode = polishMode
        cfg.polishType = polishType
        cfg.polishApiUrl = polishApiUrl
        cfg.polishApiKey = polishApiKey
        cfg.polishModel = polishModel
        cfg.polishReplyStyle = polishReplyStyle
        cfg.translateLang = translateLang
        cfg.hotkey = hotkey
        cfg.saveRecordings = saveRecordings
        cfg.cjkSpacing = cjkSpacing
        cfg.soundEnabled = soundEnabled
        cfg.llmPresets = llmPresets
        cfg.asrPresets = asrPresets
        ConfigManager.shared.config = cfg
        ConfigManager.shared.save()

        // 开机自启
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }

        // API Key 单独存 .env
        AppConfig.saveEnv(asrApiKey: asrApiKey, polishApiKey: polishApiKey, to: ensureAppDataDir())
    }

    func updateHotkeyIfNeeded(old: String) {
        guard old != hotkey else { return }
        hotkeyManager.updateHotkey(hotkey)
    }

    /// 状态栏菜单「开机自启」勾选项：勾选立即注册 SMAppService，取消立即注销，并同步到 launchAtLogin / 配置。
    @MainActor
    func toggleLaunchAtLoginFromMenu() {
        let target = !launchAtLogin
        if target {
            do {
                try SMAppService.mainApp.register()
                launchAtLogin = true
            } catch {
                NSLog("[VI] 开机自启注册失败: \(error)")
                ClipboardHelper.notify(title: "语音输入", message: "开机自启设置失败：\(error.localizedDescription)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
                launchAtLogin = false
            } catch {
                NSLog("[VI] 开机自启注销失败: \(error)")
            }
        }
        // 持久化（复用 saveConfig 里的逻辑）
        var cfg = ConfigManager.shared.config
        cfg.hotkey = hotkey
        cfg.saveRecordings = saveRecordings
        cfg.cjkSpacing = cjkSpacing
        cfg.soundEnabled = soundEnabled
        cfg.polishMode = polishMode
        cfg.polishType = polishType
        cfg.polishApiUrl = polishApiUrl
        cfg.polishModel = polishModel
        cfg.polishReplyStyle = polishReplyStyle
        cfg.translateLang = translateLang
        cfg.asrMode = asrMode
        cfg.asrProvider = asrProvider
        cfg.localModel = localModel
        cfg.llmPresets = llmPresets
        cfg.asrPresets = asrPresets
        ConfigManager.shared.config = cfg
        ConfigManager.shared.save()
    }

    // MARK: - 引导配置

    /// 从引导向导写入配置
    func applyOnboardingConfig(
        hotkey: String, asrMode: String, asrApiKey: String,
        localModel: String, polishMode: String, polishApiKey: String,
        polishApiUrl: String, polishModel: String
    ) {
        self.hotkey = hotkey
        self.asrMode = asrMode
        self.asrApiKey = asrApiKey
        self.localModel = localModel
        self.polishMode = polishMode
        self.polishApiKey = polishApiKey
        self.polishApiUrl = polishApiUrl
        self.polishModel = polishModel
        saveConfig()
    }

    /// 创建首次引导完成标记
    func markOnboarded() {
        let marker = ensureAppDataDir() + "/.onboarded"
        FileManager.default.createFile(atPath: marker, contents: nil)
    }
}
