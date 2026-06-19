import AppKit
import AVFoundation

// MARK: - 权限检测

enum PermissionChecker {
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var isMicrophoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var allGranted: Bool {
        isAccessibilityGranted && isMicrophoneGranted
    }

    static func openAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openAccessibilitySettings()
    }

    static func openMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        // .denied 状态无法通过 API 弹窗，引导用户去系统设置
        openSystemSettings()
    }

    static func openSystemSettings() {
        // 打开系统设置 → 隐私与安全性
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        } else {
            openSystemSettings()
        }
    }
}

// MARK: - 权限引导窗口

class PermissionWindow: NSWindow {
    private var timer: Timer?
    private var viewController: PermissionViewController!

    var onAllGranted: (() -> Void)?
    var onClosed: (() -> Void)?

    init() {
        // 与 ViewController.loadView 里的布局保持一致
        let W: CGFloat = 480
        let H: CGFloat = 12 + 28 + 4 + 20 + 8 + 1 + 10 + 120 + 8 + 120 + 12 + 36 + 14

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: W, height: H),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "语音输入 — 权限设置"
        isReleasedWhenClosed = false
        isRestorable = false
        center()

        let vc = PermissionViewController()
        vc.windowRef = self
        contentViewController = vc
        viewController = vc

        refresh()

        // 0.5 秒轮询权限状态
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func refresh() {
        let axOK = PermissionChecker.isAccessibilityGranted
        let micOK = PermissionChecker.isMicrophoneGranted
        viewController.updateStatus(ax: axOK, mic: micOK)
    }

    func doContinue() {
        timer?.invalidate()
        timer = nil
        orderOut(nil)
        onAllGranted?()
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        super.close()
        onClosed?()
    }
}

// MARK: - ViewController

class PermissionViewController: NSViewController {
    weak var windowRef: PermissionWindow?

    private var axBtn: NSButton!
    private var micBtn: NSButton!
    private var continueBtn: NSButton!

    override func loadView() {
        let W: CGFloat = 480
        // 紧凑布局：从上往下算
        let padTop: CGFloat = 12
        let iconSize: CGFloat = 28
        let iconTitleGap: CGFloat = 4
        let titleLineGap: CGFloat = 8
        let lineCardGap: CGFloat = 10
        let cardH: CGFloat = 120
        let cardGap: CGFloat = 8
        let cardBtnGap: CGFloat = 12
        let btnHeight: CGFloat = 36
        let padBottom: CGFloat = 14

        let H = padTop + iconSize + iconTitleGap + 20 + titleLineGap + 1 + lineCardGap + cardH + cardGap + cardH + cardBtnGap + btnHeight + padBottom

        view = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        var curY = H - padTop

        // 图标
        curY -= iconSize
        let iconView = NSImageView(frame: NSRect(x: (W - iconSize) / 2, y: curY, width: iconSize, height: iconSize))
        iconView.wantsLayer = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let url = Bundle.main.url(forResource: "menu-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: iconSize, height: iconSize)
            iconView.image = image
            iconView.contentTintColor = .labelColor
        }
        view.addSubview(iconView)

        // 标题
        curY -= iconTitleGap + 20
        let appVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "3.5"
        addCenteredLabel("Voice Input V\(appVersion)", fontSize: 16, weight: .semibold, color: .labelColor, y: curY)

        // 分割线
        curY -= titleLineGap + 1
        let line = NSView(frame: NSRect(x: 24, y: curY, width: W - 48, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        view.addSubview(line)

        // 辅助功能卡片
        curY -= lineCardGap + cardH
        let axY = curY
        let (axCard, axBtn_) = makeCard(
            y: axY,
            height: cardH,
            iconName: "keyboard",
            title: "辅助功能",
            desc: "用于监听全局快捷键和模拟键盘粘贴文本。授权后按下快捷键即可开始语音输入。",
            action: #selector(openAX)
        )
        view.addSubview(axCard)
        axBtn = axBtn_

        // 麦克风卡片
        curY -= cardGap + cardH
        let micY = curY
        let (micCard, micBtn_) = makeCard(
            y: micY,
            height: cardH,
            iconName: "mic",
            title: "麦克风",
            desc: "用于录制您的语音并转为文字。授权后才能进行语音识别。",
            action: #selector(openMic)
        )
        view.addSubview(micCard)
        micBtn = micBtn_

        // 继续使用按钮
        curY -= cardBtnGap + btnHeight
        continueBtn = NSButton(frame: NSRect(x: 120, y: curY, width: W - 240, height: btnHeight))
        continueBtn.title = "继续使用"
        continueBtn.bezelStyle = .rounded
        continueBtn.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        continueBtn.isEnabled = false
        continueBtn.target = self
        continueBtn.action = #selector(doContinue)
        view.addSubview(continueBtn)
    }

    // MARK: - 状态更新

    func updateStatus(ax: Bool, mic: Bool) {
        updateButton(axBtn, granted: ax)
        updateButton(micBtn, granted: mic)
        continueBtn.isEnabled = ax && mic
    }

    private func updateButton(_ btn: NSButton, granted: Bool) {
        if granted {
            btn.isEnabled = false
            btn.title = "✅ 已授权"
        } else {
            btn.isEnabled = true
            btn.title = "去系统设置授权"
        }
    }

    // MARK: - Actions

    @objc private func openAX() {
        PermissionChecker.openAccessibility()
    }

    @objc private func openMic() {
        PermissionChecker.openMicrophone()
    }

    @objc private func doContinue() {
        windowRef?.doContinue()
    }

    // MARK: - UI 工具

    private func addCenteredLabel(_ text: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.textColor = color
        label.alignment = .center
        label.sizeToFit()
        label.frame = NSRect(x: 0, y: y, width: view.frame.width, height: label.frame.height)
        view.addSubview(label)
    }

    private func makeCard(y: CGFloat, height: CGFloat, iconName: String, title: String, desc: String, action: Selector) -> (NSView, NSButton) {
        let cardW = view.frame.width - 48
        let cardH = height

        let card = NSView(frame: NSRect(x: 24, y: y, width: cardW, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = 1

        // 图标（SF Symbol）
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let icon = NSImageView(frame: NSRect(x: 14, y: cardH - 28, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: iconName, accessibilityDescription: title)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = iconConfig
        card.addSubview(icon)

        // 标题
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(x: 40, y: cardH - 28, width: 200, height: titleLabel.frame.height)
        card.addSubview(titleLabel)

        // 描述
        let descLabel = NSTextField(wrappingLabelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 14, y: 38, width: cardW - 28, height: 40)
        card.addSubview(descLabel)

        // 按钮
        let btn = NSButton(frame: NSRect(x: 10, y: 6, width: cardW - 20, height: 26))
        btn.title = "去系统设置授权"
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        btn.target = self
        btn.action = action
        card.addSubview(btn)

        return (card, btn)
    }
}
