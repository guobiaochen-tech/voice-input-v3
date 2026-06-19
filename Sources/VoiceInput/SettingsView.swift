import SwiftUI

// MARK: - 文件夹式标签页形状：选中标签只画上/左/右边，下边与内容区连成一体。

struct TabTopShape: Shape {
    var radius: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        // 从左上（圆角起点）顺时针：左上圆角 → 顶部直线 → 右上圆角 → 右下直角 → 左下直角 → 闭合
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct TabTopBorderShape: Shape {
    var radius: CGFloat = 6
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct PanelSideBottomBorderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

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
    var hotkeyName: String = "cmd_r" {
        didSet { updateDisplay() }
    }
    var isRecording = false {
        didSet { updateDisplay() }
    }
    var onKeyCaptured: ((String) -> Void)?

    private var heldModifiers: Set<String> = []
    private var heldKeyCode: UInt16? = nil
    private var lastComboConfig: String?
    private var hadAnyPress = false

    private var dotCount = 1
    private var dotTimer: Timer?
    private let modifierKeyCodes: Set<UInt16> = [56, 60, 59, 62, 58, 61, 55, 54, 63]

    /// 仅承载文字显示（无边框无背景，底色和边框由父 view 的 draw() 统一画，
    /// 用 #222628 与模型页 .roundedBorder TextField 内部一致）。
    private let displayField: NSTextField = {
        let f = NSTextField()
        f.isBordered = false
        f.bezelStyle = .roundedBezel
        f.isEditable = false
        f.isSelectable = false
        f.drawsBackground = false
        f.alignment = .center
        f.font = .systemFont(ofSize: 13)
        f.textColor = .labelColor
        f.usesSingleLineMode = true
        f.cell?.truncatesLastVisibleLine = true
        f.cell?.wraps = false
        return f
    }()

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(displayField)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        // NSTextField 对中文字符的垂直基线计算会偏移，导致「右 Command」这类文本上下不居中。
        // 这里把文本框高度收紧到字体实际行高，再在容器内垂直居中，保证显示对齐。
        let font = displayField.font ?? NSFont.systemFont(ofSize: 13)
        let lineHeight = ceil(font.boundingRectForFont.height)
        let h = min(lineHeight, bounds.height)
        let y = bounds.minY + round((bounds.height - h) / 2)
        displayField.frame = NSRect(x: bounds.minX, y: y, width: bounds.width, height: h)
    }

    /// 录制态高亮环（边框）需要重绘时调用
    private func updateDisplay() {
        let text: String
        let color: NSColor
        if isRecording && !comboDisplay.isEmpty {
            text = comboDisplay; color = .labelColor
        } else if isRecording {
            text = "请输入快捷键，再次点击退出" + String(repeating: ".", count: dotCount); color = .placeholderTextColor
        } else {
            text = hotkeyDisplayName(hotkeyName); color = .labelColor
        }
        displayField.stringValue = text
        displayField.textColor = color
        needsDisplay = true
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateDisplay()
    }

    private func startDotAnimation() {
        dotCount = 1
        dotTimer?.invalidate()
        dotTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dotCount = (self.dotCount % 3) + 1
            self.updateDisplay()
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
        // 填充与模型页 .roundedBorder TextField 内部一致的底色（实测 #222628）
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSColor(srgbRed: 0x22/255, green: 0x26/255, blue: 0x28/255, alpha: 1).setFill()
        path.fill()
        let border: NSColor = isRecording ? .systemBlue : .separatorColor
        border.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()
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
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 { cancelRecording(); return }
        stopDotAnimation(); hadAnyPress = true
        if !modifierKeyCodes.contains(event.keyCode) { heldKeyCode = event.keyCode }
        syncModifiers(event.modifierFlags)
        if let cfg = buildComboConfig() { lastComboConfig = cfg }
        updateDisplay()
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
        updateDisplay()
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
    @Environment(\.colorScheme) private var colorScheme

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
    @State private var polishMode: String
    @State private var polishType: String
    @State private var polishApiUrl: String
    @State private var polishApiKey: String
    @State private var polishModel: String
    @State private var polishReplyStyle: String
    @State private var translateLang: String
    @State private var availableStyles: [String] = []
    @State private var availableLangs: [String] = []

    // 预设（LLM / 云端 ASR）
    @State private var llmPresets: [ProviderPreset]
    @State private var asrPresets: [AsrPreset]
    @State private var selectedLLMPreset: String = "自定义"
    @State private var selectedASRPreset: String = "阿里云 DashScope"

    // 模型页：语音/润色 子页切换 + 检测到的可用模型
    @State private var modelSubPage: Int = 0   // 0=语音模型 1=润色模型
    @State private var availableLLMModels: [String]? = nil   // nil=未检测, []=检测为空, 有值=检测到的列表
    @State private var llmModelFetching = false

    // 模型管理
    @State private var modelTestResults: [String: Bool?] = [:]  // nil=未测试, true=可用, false=不可用
    @State private var modelDownloading: String? = nil
    @State private var modelDownloadProgress: [String: (downloaded: Int64, total: Int64)] = [:]
    @State private var modelBenchmarkResults: [String: String] = [:]

    // 测速结果
    @State private var llmSpeedResults: [String: String] = [:]        // key=模型名
    @State private var llmSpeedTesting = false
    @State private var asrCloudSpeed: String? = nil
    @State private var asrCloudTesting = false

    init() {
        let s = AppState.shared
        _hotkey = State(initialValue: s.hotkey)
        _launchAtLogin = State(initialValue: s.launchAtLogin)
        _saveRecordings = State(initialValue: s.saveRecordings)
        _soundEnabled = State(initialValue: s.soundEnabled)
        _asrMode = State(initialValue: s.asrMode)
        _asrApiKey = State(initialValue: s.asrApiKey)
        _localModel = State(initialValue: s.localModel)
        _polishMode = State(initialValue: s.polishMode)
        _polishType = State(initialValue: s.polishType)
        _polishApiUrl = State(initialValue: s.polishApiUrl)
        _polishApiKey = State(initialValue: s.polishApiKey)
        _polishModel = State(initialValue: s.polishModel)
        _polishReplyStyle = State(initialValue: s.polishReplyStyle)
        _translateLang = State(initialValue: s.translateLang)
        _llmPresets = State(initialValue: s.llmPresets)
        _asrPresets = State(initialValue: s.asrPresets)
    }

    private var hasChanges: Bool {
        hotkey != appState.hotkey ||
        launchAtLogin != appState.launchAtLogin ||
        saveRecordings != appState.saveRecordings ||
        soundEnabled != appState.soundEnabled ||
        asrMode != appState.asrMode ||
        asrApiKey != appState.asrApiKey ||
        localModel != appState.localModel ||
        polishMode != appState.polishMode ||
        polishType != appState.polishType ||
        polishApiUrl != appState.polishApiUrl ||
        polishApiKey != appState.polishApiKey ||
        polishModel != appState.polishModel ||
        polishReplyStyle != appState.polishReplyStyle ||
        translateLang != appState.translateLang
    }

    var body: some View {
        VStack(spacing: 0) {
            // 第一行：主导航（输入 / 模型）。距顶留出标题栏高度，
            // 整体居中。
            HStack(spacing: 0) {
                Spacer()
                mainTab(title: "输入", page: 0)
                mainTab(title: "模型", page: 1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // 第二行：子导航（仅模型页显示）+ 确认按钮（始终靠右）。
            // 输入页此行只有 [确认]，保证确认按钮在三个页面像素级对齐。
            HStack(spacing: 0) {
                if selectedTab == 1 {
                    modelSubTab(title: "语音模型", page: 0)
                    modelSubTab(title: "润色模型", page: 1)
                }
                Spacer()
                Button("确认") { save() }
                    .disabled(!hasChanges)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)

            // 主导航下方的分隔线，把导航区与内容区视觉切开
            Divider()
                .padding(.horizontal, 20)

            // 内容区：根据主Tab和子Tab直接切换，不再用原生 TabView（避免系统 tab bar 位置不可控）
            Group {
                if selectedTab == 0 {
                    polishTab
                } else if modelSubPage == 0 {
                    asrModelPanel
                } else {
                    llmModelPanel
                }
            }

            // 底部版本/联系方式：贴在面板最底部，左右居中
            Text("voice input V\(appVersion) · 1915199181@qq.com")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .padding(.bottom, 16)
        }
        .frame(width: 500)
        .padding(.horizontal)
        .onAppear {
            refreshModelStatus()
            availableStyles = PromptManager.availableStyles()
            availableLangs = PromptManager.availableTranslateLangs()
            syncSelectedPresetsFromCurrent()
        }
    }

    /// 读取 App 版本号（来自 Info.plist 的 CFBundleVersion），用于底部信息展示
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3.5"
    }

    // MARK: - 自绘导航按钮（主Tab / 子Tab 共用样式：选中加粗 + 底部蓝条）

    private func mainTab(title: String, page: Int) -> some View {
        navTab(title: title, page: page, selection: selectedTab, isMain: true)
    }

    private func modelSubTab(title: String, page: Int) -> some View {
        navTab(title: title, page: page, selection: modelSubPage, isMain: false)
    }

    private func navTab(title: String, page: Int, selection: Int, isMain: Bool) -> some View {
        let isSelected = selection == page
        return Button(action: {
            if isMain { selectedTab = page } else { modelSubPage = page }
        }) {
            Text(title)
                .font(.system(size: isMain ? 14 : 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 14)
                .padding(.top, 5)
                .padding(.bottom, 7)
                .fixedSize(horizontal: true, vertical: false)
                .background(alignment: .bottom) {
                    if isSelected {
                        Rectangle()
                            .fill(Color(nsColor: .controlAccentColor))
                            .frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: 语音模型面板（云端 ASR 服务商 + 本地 ASR 模型）

    private var asrModelPanel: some View {
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
                // 云端 ASR 服务商预设：选中自动填 key（各家协议后续接入）
                LabeledContent("服务商") {
                    Picker("", selection: $selectedASRPreset) {
                        ForEach(asrPresets, id: \.name) { p in
                            Text(p.name).tag(p.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
                    .onChange(of: selectedASRPreset) { oldName, newName in
                        commitCurrentASRPreset(name: oldName)
                        applyASRPreset(newName)
                    }
                }

                LabeledContent("API Key") {
                    SecureField("", text: $asrApiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                // 当前选中的服务商未接入时提示
                if let cur = asrPresets.first(where: { $0.name == selectedASRPreset }), !cur.implemented {
                    HStack {
                        Spacer()
                        Text("该服务商暂未接入，后续版本更新。当前仅阿里云 DashScope 可用。")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // 连接测速：只测建连耗时（实时 ASR 对静音不产生结果，首字延时无法稳定测得）
                LabeledContent("连接速度") {
                    HStack(spacing: 8) {
                        if let result = asrCloudSpeed {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button(asrCloudTesting ? "测速中…" : "测速") {
                            runASRCloudSpeedTest()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .disabled(asrApiKey.isEmpty || asrCloudTesting || !currentASRImplemented)
                    }
                    .frame(width: 260, alignment: .trailing)
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
                                Button("测速") {
                                    if downloaded {
                                        Task {
                                            modelTestResults[m.id] = nil
                                            if let result = LocalASRService.shared.benchmarkResult(id: m.id) {
                                                modelTestResults[m.id] = true
                                                modelBenchmarkResults[m.id] = result.display
                                            } else {
                                                modelTestResults[m.id] = false
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

    // MARK: 润色模型面板（LLM 服务商 + url/key/model + 检测/测速）

    private var llmModelPanel: some View {
        Form {
            // LLM 服务商预设：选中自动填 url + model（+ key），切走前先落回当前 key
            LabeledContent("服务商") {
                Picker("", selection: $selectedLLMPreset) {
                    ForEach(llmPresets, id: \.name) { p in
                        Text(p.name).tag(p.name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 260, alignment: .trailing)
                .onChange(of: selectedLLMPreset) { oldName, newName in
                    commitCurrentLLMPreset(name: oldName)
                    applyLLMPreset(newName)
                    // 换服务商后清空上次检测结果
                    availableLLMModels = nil
                }
            }

            LabeledContent("API 地址") {
                TextField("", text: $polishApiUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }

            LabeledContent("API Key") {
                SecureField("", text: $polishApiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
            }

            // 模型名称：检测到列表则下拉可选，否则手填
            LabeledContent("模型名称") {
                if let models = availableLLMModels, !models.isEmpty {
                    Picker("", selection: $polishModel) {
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
                } else {
                    TextField("", text: $polishModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
            }

            // 拉取：获取该 key 下的可用模型
            LabeledContent {
                HStack {
                    if llmModelFetching {
                        Text("获取中…").font(.caption).foregroundStyle(.secondary)
                    } else if let models = availableLLMModels {
                        Text(models.isEmpty ? "未获取到模型，请手填" : "已获取 \(models.count) 个模型")
                            .font(.caption)
                            .foregroundStyle(models.isEmpty ? .orange : .secondary)
                    }
                    Button(llmModelFetching ? "获取中…" : "获取模型列表") {
                        runFetchModels()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(polishApiKey.isEmpty || polishApiUrl.isEmpty || llmModelFetching)
                }
                .frame(width: 260, alignment: .trailing)
            } label: {
                Text("拉取")
            }

            // 测速：发固定短问题，测 LLM 响应延迟
            LabeledContent("响应速度") {
                HStack {
                    if let result = llmSpeedResults[polishModel] {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(llmSpeedTesting ? "测速中…" : "测速") {
                        runLLMSpeedTest()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(polishApiKey.isEmpty || polishModel.isEmpty || llmSpeedTesting)
                }
                .frame(width: 260, alignment: .trailing)
            }
        }
        .formStyle(.grouped)
    }


    // MARK: - 输入（处理流程：模式 / 风格 / 翻译语言；模型配置在「模型」Tab）

    private var polishTab: some View {
        Form {
            LabeledContent("处理模式") {
                Picker("", selection: $polishMode) {
                    Text("关闭").tag("off")
                    Text("润色").tag("polish")
                    Text("翻译").tag("translate")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 260, alignment: .trailing)
            }

            if polishMode != "off" {
                LabeledContent("回复风格") {
                    Picker("", selection: $polishReplyStyle) {
                        ForEach(availableStyles, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
                }
            }

            if polishMode == "translate" {
                LabeledContent("翻译语言") {
                    Picker("", selection: $translateLang) {
                        ForEach(availableLangs, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 260, alignment: .trailing)
                }
            }

            if polishMode == "off" {
                HStack {
                    Spacer()
                    Text("关闭后语音直接转文字，不做润色/翻译。模型配置见「模型」页。")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                }
            }

            // 下面是原「基础」设置，合并到此页底部
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

            LabeledContent("保存录音") {
                Toggle("", isOn: $saveRecordings)
                    .toggleStyle(.switch)
            }

            LabeledContent("提示音") {
                Toggle("", isOn: $soundEnabled)
                    .toggleStyle(.switch)
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
        appState.polishMode = polishMode
        appState.polishType = polishType
        appState.polishApiUrl = polishApiUrl
        appState.polishApiKey = polishApiKey
        appState.polishModel = polishModel
        appState.polishReplyStyle = polishReplyStyle
        appState.translateLang = translateLang
        appState.hotkey = hotkey
        appState.launchAtLogin = launchAtLogin
        appState.saveRecordings = saveRecordings
        appState.soundEnabled = soundEnabled
        // 把当前填的值落回预设（保留每家 key），用户手填的新值会作为历史条目留存
        commitLLMPreset()
        commitASRPreset()
        appState.llmPresets = llmPresets
        appState.asrPresets = asrPresets
        appState.saveConfig()
        appState.updateHotkeyIfNeeded(old: oldHotkey)
        appState.reinitRecognizer()

        ClipboardHelper.notify(title: "语音输入", message: "设置已保存")
        closeWindow()
    }

    private func closeWindow() {
        NSApp.keyWindow?.orderOut(nil)
    }

    // MARK: - 预设与测速辅助

    /// 当前选中的云端 ASR 是否已接入（决定能否测速/使用）
    private var currentASRImplemented: Bool {
        asrPresets.first(where: { $0.name == selectedASRPreset })?.implemented ?? false
    }

    /// 启动时根据当前 url/model/key 反查选中了哪个 LLM 预设
    private func syncSelectedPresetsFromCurrent() {
        if let p = llmPresets.first(where: { $0.apiUrl == polishApiUrl && $0.model == polishModel }) {
            selectedLLMPreset = p.name
        } else if let p = llmPresets.first(where: { !$0.isBuiltin && ($0.apiUrl == polishApiUrl || $0.model == polishModel) }) {
            selectedLLMPreset = p.name
        } else {
            selectedLLMPreset = "自定义"
        }
        if let p = asrPresets.first(where: { !$0.apiKey.isEmpty && $0.apiKey == asrApiKey }) {
            selectedASRPreset = p.name
        } else {
            selectedASRPreset = "阿里云 DashScope"
        }
    }

    /// 选中 LLM 预设 → 自动填 url + model + key（自定义则不覆盖）
    private func applyLLMPreset(_ name: String) {
        guard let p = llmPresets.first(where: { $0.name == name }) else { return }
        if p.name != "自定义" {
            if !p.apiUrl.isEmpty { polishApiUrl = p.apiUrl }
            if !p.model.isEmpty { polishModel = p.model }
            if !p.apiKey.isEmpty { polishApiKey = p.apiKey }
        }
    }

    /// 选中云端 ASR 预设 → 自动填 key；未接入的服务商不允许实际使用
    private func applyASRPreset(_ name: String) {
        guard let p = asrPresets.first(where: { $0.name == name }) else { return }
        if !p.apiKey.isEmpty { asrApiKey = p.apiKey }
    }

    /// 保存前把当前值写回预设：内置项更新 key，非内置项匹配不上则新增历史条目
    private func commitLLMPreset() {
        if let idx = llmPresets.firstIndex(where: { $0.name == selectedLLMPreset && $0.isBuiltin }) {
            llmPresets[idx].apiUrl = polishApiUrl
            llmPresets[idx].model = polishModel
            llmPresets[idx].apiKey = polishApiKey
        } else {
            // 用户自建历史：若已有同名同 url 的就更新 key，否则追加
            if let idx = llmPresets.firstIndex(where: { !$0.isBuiltin && $0.apiUrl == polishApiUrl && $0.model == polishModel }) {
                llmPresets[idx].apiKey = polishApiKey
            } else if !polishApiUrl.isEmpty || !polishModel.isEmpty {
                llmPresets.append(ProviderPreset(name: "\(polishModel)", apiUrl: polishApiUrl, model: polishModel, apiKey: polishApiKey, isBuiltin: false))
            }
        }
    }

    private func commitASRPreset() {
        if let idx = asrPresets.firstIndex(where: { $0.name == selectedASRPreset && $0.isBuiltin }) {
            asrPresets[idx].apiKey = asrApiKey
        }
    }

    /// 切走前把当前编辑中的值落回到「指定名字」的预设（保留每家 key）。
    /// onChange(oldName, newName) 里先用它落回 oldName，再 apply newName。
    private func commitCurrentLLMPreset(name: String) {
        if let idx = llmPresets.firstIndex(where: { $0.name == name && $0.isBuiltin }) {
            llmPresets[idx].apiUrl = polishApiUrl
            llmPresets[idx].model = polishModel
            llmPresets[idx].apiKey = polishApiKey
        } else if let idx = llmPresets.firstIndex(where: { $0.name == name && !$0.isBuiltin }) {
            llmPresets[idx].apiKey = polishApiKey
        }
    }

    private func commitCurrentASRPreset(name: String) {
        if let idx = asrPresets.firstIndex(where: { $0.name == name }) {
            asrPresets[idx].apiKey = asrApiKey
        }
    }

    // MARK: - 检测可用模型

    private func runFetchModels() {
        let key = polishApiKey, url = polishApiUrl
        llmModelFetching = true
        availableLLMModels = nil
        Task {
            let models = await TextPolisher.fetchAvailableModels(apiKey: key, apiUrl: url)
            await MainActor.run {
                llmModelFetching = false
                availableLLMModels = models ?? []
                // 若当前模型名不在列表里，且列表非空，选第一个
                if let list = availableLLMModels, !list.isEmpty, !list.contains(polishModel) {
                    polishModel = list.first ?? polishModel
                }
            }
        }
    }

    // MARK: - 测速

    private func runLLMSpeedTest() {
        let key = polishApiKey, model = polishModel, url = polishApiUrl
        llmSpeedTesting = true
        Task {
            let result = await TextPolisher().measureLatency(apiKey: key, model: model, apiUrl: url)
            await MainActor.run {
                llmSpeedTesting = false
                llmSpeedResults[model] = result?.display ?? "测速失败（检查 Key/URL/模型名）"
            }
        }
    }

    private func runASRCloudSpeedTest() {
        guard currentASRImplemented else { return }
        let key = asrApiKey
        asrCloudTesting = true
        asrCloudSpeed = nil
        Task {
            let ms = await Transcriber().measureConnectionLatency(apiKey: key)
            await MainActor.run {
                asrCloudTesting = false
                if let ms {
                    asrCloudSpeed = "连接 \(ms)ms"
                } else {
                    asrCloudSpeed = "测速失败（检查网络/API Key）"
                }
            }
        }
    }
}
