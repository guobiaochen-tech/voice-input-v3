import SwiftUI

// MARK: - 原生下拉框（从 v2 保留）

struct PopupButton: NSViewRepresentable {
    var options: [(tag: String, title: String)]
    @Binding var selection: String

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton()
        button.isBordered = true
        button.bezelStyle = .rounded
        button.addItems(withTitles: options.map(\.title))
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed)
        return button
    }

    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        let width = max(nsView.frame.width, 240)
        if let menu = nsView.menu {
            menu.minimumWidth = width
        }

        for (i, option) in options.enumerated() {
            guard let item = nsView.item(at: i) else { continue }
            item.representedObject = option.tag
            item.view = RightAlignedMenuItemView(
                title: option.title,
                menuItem: item,
                width: width
            )
        }

        if let idx = options.firstIndex(where: { $0.tag == selection }) {
            nsView.selectItem(at: idx)
        }
        nsView.cell?.alignment = .right
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        let parent: PopupButton
        init(_ parent: PopupButton) { self.parent = parent }

        @objc func changed(_ sender: NSPopUpButton) {
            guard let tag = sender.selectedItem?.representedObject as? String else { return }
            parent.selection = tag
        }
    }
}

private class RightAlignedMenuItemView: NSView {
    private let title: String
    private weak var menuItem: NSMenuItem?

    init(title: String, menuItem: NSMenuItem, width: CGFloat) {
        self.title = title
        self.menuItem = menuItem
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = [.width]
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) {
        guard let menu = menuItem?.menu, let item = menuItem else {
            super.mouseUp(with: event)
            return
        }
        menu.cancelTracking()
        if let index = menu.items.firstIndex(of: item) {
            menu.performActionForItem(at: index)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = menuItem?.menu?.highlightedItem === menuItem

        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            bounds.fill()
        }

        let textColor: NSColor = highlighted ? .white : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: textColor,
        ]
        let textSize = (title as NSString).size(withAttributes: attrs)
        let x = bounds.width - textSize.width - 16
        let y = (bounds.height - textSize.height) / 2
        (title as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
}



// MARK: - 快捷键录制器（点击后按任意键录制）

/// 显示快捷键名称（支持组合键如 alt+c → ⌥C）
private func hotkeyDisplayName(_ config: String) -> String {
    let parts = config.split(separator: "+").map(String.init)
    if parts.count == 1 {
        return HOTKEY_DISPLAY[parts[0]] ?? parts[0].uppercased()
    }
    let modSymbols: [String: String] = ["ctrl": "⌃", "shift": "⇧", "alt": "⌥", "cmd": "⌘"]
    let modStr = ["ctrl", "shift", "alt", "cmd"]
        .filter { m in parts.dropLast().contains(m) }
        .compactMap { modSymbols[$0] }
        .joined()
    let keyDisplay = HOTKEY_DISPLAY[parts.last!] ?? parts.last!.uppercased()
    return modStr + keyDisplay
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: String

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.hotkeyName = hotkey
        view.onKeyCaptured = { [self] name in
            DispatchQueue.main.async {
                hotkey = name
            }
        }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.hotkeyName = hotkey
        nsView.needsDisplay = true
    }
}

class RecorderView: NSView {
    var hotkeyName: String = "cmd_r"
    var isRecording = false
    var onKeyCaptured: ((String) -> Void)?

    private var heldModifiers: Set<String> = []
    private var heldKeyCode: UInt16? = nil
    private var lastComboConfig: String?
    private var hadAnyPress = false

    private var dotCount = 1
    private var dotTimer: Timer?
    private let modifierKeyCodes: Set<UInt16> = [56, 60, 59, 62, 58, 61, 55, 54, 63]

    override var acceptsFirstResponder: Bool { true }

    private func startDotAnimation() {
        dotCount = 1
        dotTimer?.invalidate()
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dotCount = (self.dotCount % 3) + 1
            self.needsDisplay = true
        }
    }

    private func stopDotAnimation() {
        dotTimer?.invalidate()
        dotTimer = nil
        dotCount = 1
    }

    private var comboDisplay: String {
        let symbols = ["ctrl": "⌃", "shift": "⇧", "alt": "⌥", "cmd": "⌘"]
        let modStr = ["ctrl", "shift", "alt", "cmd"]
            .filter { heldModifiers.contains($0) }
            .compactMap { symbols[$0] }
            .joined()
        if let kc = heldKeyCode, let m = KEYCODE_MAP[kc] {
            return modStr + m.displayName
        }
        return modStr.isEmpty ? "" : modStr
    }

    private func buildComboConfig() -> String? {
        guard let kc = heldKeyCode, let m = KEYCODE_MAP[kc] else { return nil }
        if heldModifiers.isEmpty { return m.configName }
        let mods = ["ctrl", "shift", "alt", "cmd"].filter { heldModifiers.contains($0) }
        return (mods + [m.configName]).joined(separator: "+")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        path.fill()
        let border: NSColor = isRecording ? .systemBlue : .separatorColor
        border.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording && !comboDisplay.isEmpty {
            text = comboDisplay; color = .labelColor
        } else if isRecording {
            text = "请输入快捷键，再次点击退出" + String(repeating: ".", count: dotCount); color = .placeholderTextColor
        } else {
            text = hotkeyDisplayName(hotkeyName); color = .labelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color]
        let sz = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            cancelRecording()
            return
        }
        isRecording = true
        heldModifiers = []; heldKeyCode = nil; lastComboConfig = nil; hadAnyPress = false
        startDotAnimation()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 { cancelRecording(); return }
        stopDotAnimation(); hadAnyPress = true
        if !modifierKeyCodes.contains(event.keyCode) { heldKeyCode = event.keyCode }
        syncModifiers(event.modifierFlags)
        if let cfg = buildComboConfig() { lastComboConfig = cfg }
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        guard isRecording else { return }
        if heldKeyCode == event.keyCode {
            heldKeyCode = nil
            if heldModifiers.isEmpty && lastComboConfig != nil { finalizeCapture(); return }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        stopDotAnimation(); hadAnyPress = true
        syncModifiers(event.modifierFlags)
        if heldModifiers.isEmpty {
            if lastComboConfig != nil { finalizeCapture(); return }
            if heldKeyCode == nil, hadAnyPress, let m = KEYCODE_MAP[event.keyCode] {
                lastComboConfig = m.configName; finalizeCapture(); return
            }
        }
        needsDisplay = true
    }

    private func syncModifiers(_ flags: NSEvent.ModifierFlags) {
        heldModifiers = []
        if flags.contains(.control) { heldModifiers.insert("ctrl") }
        if flags.contains(.shift) { heldModifiers.insert("shift") }
        if flags.contains(.option) { heldModifiers.insert("alt") }
        if flags.contains(.command) { heldModifiers.insert("cmd") }
    }

    private func finalizeCapture() {
        let cfg = lastComboConfig ?? ""
        isRecording = false
        heldModifiers = []; heldKeyCode = nil; hadAnyPress = false; lastComboConfig = nil
        stopDotAnimation()
        if !cfg.isEmpty { onKeyCaptured?(cfg) }
        needsDisplay = true
    }

    private func cancelRecording() {
        isRecording = false
        heldModifiers = []; heldKeyCode = nil; hadAnyPress = false; lastComboConfig = nil
        stopDotAnimation(); needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }; return true
    }
}

// MARK: - 设置界面（3 栏：基础 + 识别 + 润色）

struct SettingsView: View {
    @Environment(AppState.self) var appState

    @State private var selectedTab: Int = 0

    // 基础
    @State private var hotkey: String
    @State private var launchAtLogin: Bool
    @State private var saveRecordings: Bool
    @State private var soundEnabled: Bool

    // 识别
    @State private var asrMode: String
    @State private var asrApiKey: String
    @State private var localModel: String
    @State private var localModels: [String] = []

    // 润色
    @State private var polishEnabled: Bool
    @State private var polishType: String
    @State private var polishApiUrl: String
    @State private var polishApiKey: String
    @State private var polishModel: String

    // 模型管理
    @State private var modelTestResults: [String: Bool?] = [:]  // nil=未测试, true=可用, false=不可用
    @State private var modelDownloading: String? = nil
    @State private var modelDownloadProgress: [String: (downloaded: Int64, total: Int64)] = [:]
    @State private var modelBenchmarkResults: [String: String] = [:]

    init() {
        let s = AppState.shared
        _hotkey = State(initialValue: s.hotkey)
        _launchAtLogin = State(initialValue: s.launchAtLogin)
        _saveRecordings = State(initialValue: s.saveRecordings)
        _soundEnabled = State(initialValue: s.soundEnabled)
        _asrMode = State(initialValue: s.asrMode)
        _asrApiKey = State(initialValue: s.asrApiKey)
        _localModel = State(initialValue: s.localModel)
        _polishEnabled = State(initialValue: s.polishEnabled)
        _polishType = State(initialValue: s.polishType)
        _polishApiUrl = State(initialValue: s.polishApiUrl)
        _polishApiKey = State(initialValue: s.polishApiKey)
        _polishModel = State(initialValue: s.polishModel)
    }

    private var hasChanges: Bool {
        hotkey != appState.hotkey ||
        launchAtLogin != appState.launchAtLogin ||
        saveRecordings != appState.saveRecordings ||
        soundEnabled != appState.soundEnabled ||
        asrMode != appState.asrMode ||
        asrApiKey != appState.asrApiKey ||
        localModel != appState.localModel ||
        polishEnabled != appState.polishEnabled ||
        polishType != appState.polishType ||
        polishApiUrl != appState.polishApiUrl ||
        polishApiKey != appState.polishApiKey ||
        polishModel != appState.polishModel
    }

    var body: some View {
        VStack(spacing: 8) {
            // 顶部按钮栏
            HStack {
                if selectedTab == 2 {
                    Toggle("启用润色", isOn: $polishEnabled)
                }
                Spacer()
                Button("确认") { save() }
                    .disabled(!hasChanges)
            }
            .padding(.horizontal, 20)

            TabView(selection: $selectedTab) {
                basicTab
                    .tabItem { Text("基础") }
                    .tag(0)

                asrTab
                    .tabItem { Text("输入识别") }
                    .tag(1)

                polishTab
                    .tabItem { Text("润色") }
                    .tag(2)
            }
        }
        .frame(width: 500)
        .padding()
        .onAppear {
            refreshModelStatus()
        }
    }

    // MARK: - 基础

    private var basicTab: some View {
        Form {
            HStack {
                Text("快捷键")
                Spacer()
                HotkeyRecorder(hotkey: $hotkey)
                    .frame(width: 260, height: 28)
            }

            if let warning = KEY_CONFLICTS[hotkey] {
                HStack {
                    Spacer()
                    Text(warning)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            LabeledContent("开机自启动") {
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
            }

            LabeledContent("保存录音") {
                Toggle("", isOn: $saveRecordings)
                    .toggleStyle(.switch)
            }

            LabeledContent("提示音") {
                Toggle("", isOn: $soundEnabled)
                    .toggleStyle(.switch)
            }

            Divider()

            HStack {
                Spacer()
                Text("Voice Input v3.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 识别

    private var asrTab: some View {
        Form {
            LabeledContent("识别模式") {
                PopupButton(
                    options: [
                        ("cloud", "云端识别"),
                        ("local", "本地识别"),
                    ],
                    selection: $asrMode
                )
                .frame(width: 260)
            }

            if asrMode == "cloud" {
                LabeledContent("API Key") {
                    SecureField("", text: $asrApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                HStack {
                    Spacer()
                    Text("请填入云端 ASR 服务的 API Key（支持阿里云、腾讯云、讯飞等）")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                // 模型列表：点击已安装的行选中
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(ModelManager.supportedModels, id: \.id) { m in
                        let downloaded = localModels.contains(m.id)
                        let testResult = modelTestResults[m.id]
                        let isThisDownloading = modelDownloading == m.id
                        let isSelected = localModel == m.id && downloaded

                        HStack(spacing: 8) {
                            // 选中指示
                            Text(downloaded ? "●" : "○")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : Color(nsColor: .separatorColor))
                                .frame(width: 14)

                            // 模型名 + 大小
                            Text("\(m.name)  \(m.size)")
                                .font(.caption)

                            Spacer()

                            // 测试结果
                            if let bench = modelBenchmarkResults[m.id] {
                                Text(bench)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let result = testResult {
                                Text(result == true ? "可用" : "不可用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // 测试按钮
                            if downloaded || m.downloadBaseURL != nil {
                                Button("测试") {
                                    if downloaded {
                                        Task {
                                            modelTestResults[m.id] = nil
                                            let result = LocalASRService.shared.benchmark(id: m.id)
                                            modelTestResults[m.id] = result != nil ? true : false
                                            // 用不同 key 存结果文字
                                            if let r = result {
                                                modelBenchmarkResults[m.id] = r
                                            }
                                        }
                                    } else {
                                        Task {
                                            modelTestResults[m.id] = nil
                                            let ok = await ModelManager.shared.testDownloadURL(for: m.id)
                                            modelTestResults[m.id] = ok
                                        }
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
                                            try await ModelManager.shared.downloadModel(id: m.id) { _, downloaded, total in
                                                Task { @MainActor in
                                                    modelDownloadProgress[m.id] = (downloaded, total)
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

                            // 删除按钮
                            if downloaded && !isThisDownloading {
                                Button("删除") {
                                    do {
                                        try ModelManager.shared.deleteModel(id: m.id)
                                        localModels = ModelManager.shared.scanLocalModels()
                                        if !localModels.contains(localModel) {
                                            localModel = localModels.first ?? localModel
                                        }
                                    } catch {
                                        NSLog("[VI] 模型删除失败: \(error)")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
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
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 润色

    private var polishTab: some View {
        Form {
            LabeledContent("模型来源") {
                Text("云模型")
                    .frame(width: 260, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("API 地址") {
                TextField("", text: $polishApiUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .disabled(!polishEnabled)
            }

            LabeledContent("API Key") {
                SecureField("", text: $polishApiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .disabled(!polishEnabled)
            }

            LabeledContent("模型名称") {
                TextField("", text: $polishModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .disabled(!polishEnabled)
            }
        }
        .formStyle(.grouped)
    }


    // MARK: - 模型操作

    private func refreshModelStatus() {
        localModels = ModelManager.shared.scanLocalModels()
        if !localModels.contains(localModel) {
            localModel = localModels.first ?? localModel
        }
    }

    // MARK: - 保存

    private func save() {
        let oldHotkey = appState.hotkey

        appState.asrEngine = "third_party"
        appState.asrProvider = ""
        appState.asrApiKey = asrApiKey
        appState.asrMode = asrMode
        appState.localModel = localModel
        appState.polishEnabled = polishEnabled
        appState.polishType = polishType
        appState.polishApiUrl = polishApiUrl
        appState.polishApiKey = polishApiKey
        appState.polishModel = polishModel
        appState.hotkey = hotkey
        appState.launchAtLogin = launchAtLogin
        appState.saveRecordings = saveRecordings
        appState.soundEnabled = soundEnabled
        appState.saveConfig()
        appState.updateHotkeyIfNeeded(old: oldHotkey)
        appState.reinitRecognizer()

        ClipboardHelper.notify(title: "语音输入", message: "设置已保存")
        closeWindow()
    }

    private func closeWindow() {
        NSApp.keyWindow?.orderOut(nil)
    }
}
