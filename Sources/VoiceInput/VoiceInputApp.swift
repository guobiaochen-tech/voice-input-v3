import SwiftUI

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var instance: AppDelegate?
    private var statusItem: NSStatusItem!
    private var settingsPanel: NSPanel?

    override init() {
        super.init()
        AppDelegate.instance = self
    }

    private var permissionWindow: PermissionWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        // 默认提示词 md 与权限无关，启动即生成（不依赖 AppState 初始化时机）
        PromptManager.ensureDefaults()

        if PermissionChecker.allGranted {
            proceedAfterPermission()
        } else {
            showPermissionWindow()
        }
    }

    private func proceedAfterPermission() {
        setupStatusItem()
        AppState.shared.setup()
        observeState()
    }

    private func showPermissionWindow() {
        let pw = PermissionWindow()
        pw.onAllGranted = { [weak self] in
            self?.permissionWindow = nil
            self?.proceedAfterPermission()
        }
        pw.onClosed = { [weak self] in
            self?.permissionWindow = nil
            NSApp.terminate(nil)
        }
        pw.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = pw
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.hotkeyManager.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let url = Bundle.main.url(forResource: "menu-icon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Voice Input")
            }
        }

        rebuildMenu()
    }

    private func observeState() {
        withObservationTracking {
            _ = AppState.shared.isRecording
            _ = AppState.shared.isProcessing
            _ = AppState.shared.statusText
            _ = AppState.shared.hotkey
            _ = AppState.shared.asrMode
            _ = AppState.shared.polishMode
            _ = AppState.shared.polishModel
            _ = AppState.shared.translateLang
            _ = AppState.shared.launchAtLogin
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateStatusItem() }
        }
    }

    private func updateStatusItem() {
        rebuildMenu()
        observeState()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let state = AppState.shared

        // 动态状态：录音/处理中才显示，就绪时不显示状态文字
        if state.isRecording || state.isProcessing {
            let statusText = state.isRecording ? "录音中..." : "处理中..."
            let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusMenuItem.isEnabled = false
            menu.addItem(statusMenuItem)
        }

        // 快捷键
        let hkDisplay = HOTKEY_DISPLAY[state.hotkey] ?? state.hotkey.uppercased()
        let hkItem = NSMenuItem(title: "快捷键: \(hkDisplay)", action: nil, keyEquivalent: "")
        hkItem.isEnabled = false
        menu.addItem(hkItem)

        // 识别模型：(本地 / 阿里云)
        let asrDisplay: String
        if state.asrMode == "local" {
            asrDisplay = "本地"
        } else {
            asrDisplay = "阿里云"
        }
        let asrItem = NSMenuItem(title: "识别模型: \(asrDisplay)", action: nil, keyEquivalent: "")
        asrItem.isEnabled = false
        menu.addItem(asrItem)

        // 润色模型：(关闭 / kimi 等)
        let polishDisplay: String
        switch state.polishMode {
        case "off": polishDisplay = "关闭"
        case "translate": polishDisplay = "翻译(\(state.translateLang))"
        default: polishDisplay = state.polishModel.isEmpty ? "润色" : state.polishModel
        }
        let polishItem = NSMenuItem(title: "润色模型: \(polishDisplay)", action: nil, keyEquivalent: "")
        polishItem.isEnabled = false
        menu.addItem(polishItem)

        menu.addItem(.separator())

        // 开机自启（勾选在文字左边）：勾选立即注册 SMAppService，取消立即注销
        let launchItem = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = state.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func showSettings() {
        if let panel = settingsPanel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView().environment(AppState.shared)
        let panel = NSPanel(
            contentRect: NSMakeRect(0, 0, 532, 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Voice Input 语音输入设置"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsPanel = panel
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        AppState.shared.toggleLaunchAtLoginFromMenu()
        sender.state = AppState.shared.launchAtLogin ? .on : .off
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
