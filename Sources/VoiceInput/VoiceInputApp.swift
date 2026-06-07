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

        // 状态
        let statusText: String
        if state.isRecording {
            statusText = "录音中..."
        } else if state.isProcessing {
            statusText = "处理中..."
        } else {
            statusText = state.statusText
        }

        let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // ASR 模式
        let modeText = state.asrMode == "local" ? "本地识别" : "云端识别"
        let modeItem = NSMenuItem(title: "模式: \(modeText)", action: nil, keyEquivalent: "")
        modeItem.isEnabled = false
        menu.addItem(modeItem)

        menu.addItem(.separator())
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
            contentRect: NSMakeRect(0, 0, 540, 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "语音输入设置"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsPanel = panel
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
