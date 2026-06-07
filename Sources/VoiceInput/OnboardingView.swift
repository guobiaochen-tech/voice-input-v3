import SwiftUI
import AVFoundation

// MARK: - 首次启动引导向导

struct OnboardingView: View {
    @Environment(AppState.self) var appState

    @State private var currentStep = 0
    let totalSteps = 6  // 0-5

    // 设置项
    @State private var hotkey: String = "fn"
    @State private var asrMode: String = "cloud"
    @State private var asrApiKey: String = ""
    @State private var localModel: String = "sensevoice-small"
    @State private var polishEnabled: Bool = true
    @State private var polishApiUrl: String = "https://api.deepseek.com/chat/completions"
    @State private var polishApiKey: String = ""
    @State private var polishModel: String = "deepseek-v4-flash"

    // 权限状态
    @State private var accessibilityGranted = false
    @State private var microphoneGranted = false
    @State private var permissionTimer: Timer?

    // 模型
    @State private var localModels: [String] = []
    @State private var modelTestResults: [String: Bool?] = [:]
    @State private var modelDownloading: String? = nil
    @State private var modelDownloadProgress: [String: (downloaded: Int64, total: Int64)] = [:]
    @State private var modelBenchmarkResults: [String: String] = [:]

    // 完成回调
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // 主内容区
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: accessibilityStep
                case 2: microphoneStep
                case 3: hotkeyStep
                case 4: asrModeStep
                case 5: polishStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 32)

            // 底部导航栏
            bottomBar
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
                .padding(.top, 12)
        }
        .frame(width: 580, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            localModels = ModelManager.shared.scanLocalModels()
        }
    }

    // MARK: - 底部导航

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Divider()

            HStack {
                // 步骤圆点
                HStack(spacing: 8) {
                    ForEach(0...totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color(nsColor: .labelColor) : Color(nsColor: .separatorColor))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                // 跳过按钮（最后一步不显示）
                if currentStep < totalSteps {
                    Button("跳过") {
                        advanceStep()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                // 上一步
                if currentStep > 0 && currentStep < totalSteps {
                    Button("上一步") {
                        currentStep -= 1
                        stopPermissionTimer()
                    }
                    .buttonStyle(.plain)
                }

                // 下一步 / 开始使用
                if currentStep < totalSteps {
                    Button(nextButtonText) {
                        handleNext()
                    }
                    .disabled(!canProceed)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var nextButtonText: String {
        switch currentStep {
        case 0: return "开始使用"
        case 4: return asrMode == "cloud" && asrApiKey.isEmpty ? "跳过此项" : "下一步"
        default: return "下一步"
        }
    }

    private var canProceed: Bool {
        return true
    }

    // MARK: - Step 0: 欢迎页

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
            }

            Text("语音输入")
                .font(.system(size: 28, weight: .semibold))

            Text("按下快捷键，说话即输入。\n支持云端和本地语音识别。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Step 1: 辅助功能权限

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: accessibilityGranted ? "lock.shield.fill" : "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("辅助功能权限")
                .font(.system(size: 22, weight: .semibold))

            Text("语音输入需要辅助功能权限来模拟键盘输入，\n将识别结果粘贴到当前光标位置。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !accessibilityGranted {
                Button("打开系统设置") {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as NSDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                }
                .buttonStyle(.borderedProminent)
                .onAppear { startPermissionTimer() }
                .onDisappear { stopPermissionTimer() }
            } else {
                Text("已授权")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Step 2: 麦克风权限

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: microphoneGranted ? "mic.fill" : "mic")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("麦克风权限")
                .font(.system(size: 22, weight: .semibold))

            Text("语音输入需要麦克风权限来录制您的语音。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !microphoneGranted {
                Button("请求权限") {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        Task { @MainActor in
                            checkMicrophoneStatus()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .onAppear { startPermissionTimer() }
                .onDisappear { stopPermissionTimer() }
            } else {
                Text("已授权")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Step 3: 快捷键

    private var hotkeyStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("快捷键设置")
                .font(.system(size: 22, weight: .semibold))

            Text("选择一个快捷键来触发语音输入。\n松开快捷键时自动结束录音并输入文字。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HotkeyRecorder(hotkey: $hotkey)
                .frame(width: 260, height: 32)

            if let warning = KEY_CONFLICTS[hotkey] {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
    }

    // MARK: - Step 4: 识别模式

    private var asrModeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("选择识别模式")
                .font(.system(size: 22, weight: .semibold))

            HStack(spacing: 16) {
                // 云端选项
                modeCard(
                    icon: "cloud.fill",
                    title: "云端识别",
                    subtitle: "使用云端 API，准确率高",
                    selected: asrMode == "cloud"
                ) { asrMode = "cloud" }

                // 本地选项
                modeCard(
                    icon: "desktopcomputer",
                    title: "本地识别",
                    subtitle: "本地运行模型，无需网络",
                    selected: asrMode == "local"
                ) { asrMode = "local" }
            }

            // 条件内容
            if asrMode == "cloud" {
                VStack(spacing: 8) {
                    SecureField("API Key", text: $asrApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                    Text("请填入云端 ASR 服务的 API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                // 本地模型列表：全部列出，可下载，点击已安装的行选中
                VStack(spacing: 3) {
                    ForEach(ModelManager.supportedModels, id: \.id) { m in
                        let downloaded = localModels.contains(m.id)
                        let isThisDownloading = modelDownloading == m.id
                        let isSelected = localModel == m.id && downloaded

                        HStack(spacing: 8) {
                            // 选中指示
                            Text(downloaded ? "●" : "○")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor))
                                .frame(width: 14)

                            Text("\(m.name)  \(m.size)")
                                .font(.caption)

                            Spacer()

                            // 测试结果
                            if let result = modelTestResults[m.id] {
                                Text(result == true ? "可用" : "不可用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // 测试按钮（只测下载地址是否可用）
                            if m.downloadBaseURL != nil {
                                Button("测试") {
                                    Task {
                                        modelTestResults[m.id] = nil
                                        let ok = await ModelManager.shared.testDownloadURL(for: m.id)
                                        modelTestResults[m.id] = ok
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .disabled(modelDownloading != nil)
                            }

                            // 下载按钮
                            if !downloaded && m.downloadBaseURL != nil && !isThisDownloading {
                                Button("下载") {
                                    Task {
                                        modelDownloading = m.id
                                        modelDownloadProgress[m.id] = (0, 0)
                                        do {
                                            try await ModelManager.shared.downloadModel(id: m.id) { _, d, t in
                                                Task { @MainActor in
                                                    modelDownloadProgress[m.id] = (d, t)
                                                }
                                            }
                                            localModels = ModelManager.shared.scanLocalModels()
                                            if localModels.contains(m.id) {
                                                localModel = m.id
                                            }
                                        } catch {
                                            NSLog("[VI] 模型下载失败: \(error)")
                                        }
                                        modelDownloading = nil
                                        modelDownloadProgress.removeValue(forKey: m.id)
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .disabled(modelDownloading != nil)
                            }

                            // 下载进度
                            if isThisDownloading, let prog = modelDownloadProgress[m.id], prog.total > 0 {
                                let pct = Double(prog.downloaded) / Double(prog.total)
                                Text(String(format: "%.0f%%", pct * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard downloaded else { return }
                            localModel = m.id
                        }
                    }
                }
                .frame(width: 460)
            }

            Spacer()
        }
    }

    private func modeCard(icon: String, title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(selected ? .primary : .secondary)

                Text(title)
                    .font(.system(size: 14, weight: .medium))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 150, height: 110)
            .background(selected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 5: 润色设置

    private var polishStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("文本润色")
                .font(.system(size: 22, weight: .semibold))

            Text("自动修正识别错误、去除口头禅、添加标点。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Toggle("启用文本润色", isOn: $polishEnabled)
                .toggleStyle(.switch)

            if polishEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("API 地址")
                            .frame(width: 70, alignment: .trailing)
                        TextField("", text: $polishApiUrl)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("模型")
                            .frame(width: 70, alignment: .trailing)
                        TextField("", text: $polishModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("API Key")
                            .frame(width: 70, alignment: .trailing)
                        SecureField("", text: $polishApiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(width: 380)
            }

            Spacer()
        }
    }

    // MARK: - Step 6: 完成

    private var doneStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("设置完成")
                .font(.system(size: 22, weight: .semibold))

            // 配置摘要
            VStack(alignment: .leading, spacing: 8) {
                summaryRow("快捷键", value: HOTKEY_DISPLAY[hotkey] ?? hotkey)
                summaryRow("识别模式", value: asrMode == "cloud" ? "云端识别" : "本地识别")
                summaryRow("文本润色", value: polishEnabled ? "已开启" : "已关闭")
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("开始使用") {
                finishOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(size: 13))
    }

    // MARK: - 导航逻辑

    private func handleNext() {
        if currentStep == totalSteps {
            finishOnboarding()
        } else {
            advanceStep()
        }
    }

    private func advanceStep() {
        stopPermissionTimer()
        currentStep += 1

        // 进入权限步骤时启动轮询
        if currentStep == 1 {
            accessibilityGranted = AXIsProcessTrusted()
        } else if currentStep == 2 {
            checkMicrophoneStatus()
        }
    }

    private func finishOnboarding() {
        appState.applyOnboardingConfig(
            hotkey: hotkey,
            asrMode: asrMode,
            asrApiKey: asrApiKey,
            localModel: localModel,
            polishEnabled: polishEnabled,
            polishApiKey: polishApiKey,
            polishApiUrl: polishApiUrl,
            polishModel: polishModel
        )
        appState.markOnboarded()
        onComplete?()
    }

    // MARK: - 权限轮询

    private func startPermissionTimer() {
        stopPermissionTimer()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                if currentStep == 1 {
                    accessibilityGranted = AXIsProcessTrusted()
                } else if currentStep == 2 {
                    checkMicrophoneStatus()
                }
            }
        }
    }

    private func stopPermissionTimer() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func checkMicrophoneStatus() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
