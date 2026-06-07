import Cocoa

/// 全局快捷键监听（CGEvent tap）
/// 支持：单键、修饰键、组合键（如 alt+c）
class HotkeyManager {
    var targetKeycode: UInt16 = 54 // 右 Command
    var targetModifiers: Set<String> = []  // "alt", "cmd", "shift", "ctrl"
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)? // ESC 取消

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var checkTimer: Timer?
    private var isPressed = false
    private var retainedSelfPtr: UnsafeMutableRawPointer?

    /// tap 是否正常工作
    private(set) var isTapActive = false

    func start() {
        stop()

        // 尝试创建 tap
        tryCreateTap()

        // 启动周期性检查（参考 Typeoff：每 2 秒检查权限 + tap 状态）
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.periodicCheck()
        }
    }

    private func tryCreateTap() {
        if createTap() {
            isTapActive = true
            NSLog("[VI] CGEvent tap 创建成功")
        } else {
            isTapActive = false
            NSLog("[VI] CGEvent tap 创建失败，等待辅助功能授权...")
        }
    }

    /// 周期性检查（类似 Typeoff 的 checkPermissions）
    private func periodicCheck() {
        guard AXIsProcessTrusted() else {
            if isTapActive {
                NSLog("[VI] 辅助功能权限失效，停止 CGEvent tap")
                invalidateTap()
            }
            return
        }

        if let tap = eventTap, CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) {
            isTapActive = true
            return
        }

        if eventTap != nil || isTapActive {
            NSLog("[VI] CGEvent tap 已失效，准备重建")
            invalidateTap()
        }

        NSLog("[VI] 辅助功能已授权，重新创建 CGEvent tap")
        tryCreateTap()
    }

    private func createTap() -> Bool {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        retainedSelfPtr = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                manager.handleCGEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: retainedSelfPtr
        ) else {
            if let ptr = retainedSelfPtr {
                Unmanaged<HotkeyManager>.fromOpaque(ptr).release()
                retainedSelfPtr = nil
            }
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
        invalidateTap()
    }

    private func invalidateTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            if let ptr = retainedSelfPtr {
                Unmanaged<HotkeyManager>.fromOpaque(ptr).release()
                retainedSelfPtr = nil
            }
        }
        eventTap = nil
        runLoopSource = nil
        isTapActive = false
        isPressed = false
    }

    /// 更新快捷键配置（支持组合键如 "alt+c"）
    func updateHotkey(_ config: String) {
        let parts = config.split(separator: "+").map(String.init)
        targetModifiers = []
        if parts.count > 1 {
            for i in 0..<(parts.count - 1) {
                let p = parts[i]
                if ["alt", "cmd", "shift", "ctrl"].contains(p) {
                    targetModifiers.insert(p)
                }
            }
        }
        let keyName = parts.last ?? "cmd_r"
        targetKeycode = HOTKEY_KEYCODE[keyName] ?? 54
    }

    /// 兼容旧接口
    func updateKeycode(_ keycode: UInt16) {
        targetKeycode = keycode
        targetModifiers = []
    }

    // MARK: - Private

    private let modifierKeyCodes: Set<UInt16> = [56, 60, 59, 62, 58, 61, 55, 54, 63]

    private func handleCGEvent(type: CGEventType, event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = CGEventFlags(rawValue: event.flags.rawValue)

        // ESC 取消
        if type == .keyDown && keyCode == 53 {
            DispatchQueue.main.async { [weak self] in
                self?.onCancel?()
            }
            return
        }

        let isModifier = modifierKeyCodes.contains(keyCode)

        // 组合键模式：检查修饰键是否匹配
        let currentModifiers = cgFlagsToModSet(flags)
        let modifiersMatch = targetModifiers.isEmpty || currentModifiers == targetModifiers

        if !targetModifiers.isEmpty {
            // 组合键模式（如 alt+c）
            switch type {
            case .keyDown where !isModifier:
                if keyCode == targetKeycode && modifiersMatch && !isPressed {
                    isPressed = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onPress?()
                    }
                }
            case .keyUp where !isModifier:
                if keyCode == targetKeycode && isPressed {
                    isPressed = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onRelease?()
                    }
                }
            default:
                break
            }
        } else {
            // 单键模式（原有逻辑）
            guard keyCode == targetKeycode else { return }

            switch type {
            case .keyDown where !isModifier:
                if !isPressed {
                    isPressed = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onPress?()
                    }
                }
            case .keyUp where !isModifier:
                if isPressed {
                    isPressed = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onRelease?()
                    }
                }
            case .flagsChanged:
                let targetFlag: CGEventFlags
                switch keyCode {
                case 56, 60: targetFlag = .maskShift
                case 59, 62: targetFlag = .maskControl
                case 58, 61: targetFlag = .maskAlternate
                case 55, 54: targetFlag = .maskCommand
                case 63: targetFlag = CGEventFlags(rawValue: 0x800000) // Fn
                default: return
                }
                let nowPressed = flags.contains(targetFlag)
                if nowPressed && !isPressed {
                    isPressed = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onPress?()
                    }
                } else if !nowPressed && isPressed {
                    isPressed = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onRelease?()
                    }
                }
            default:
                break
            }
        }
    }

    /// CGEventFlags → 修饰键名称集合
    private func cgFlagsToModSet(_ flags: CGEventFlags) -> Set<String> {
        var mods: Set<String> = []
        if flags.contains(.maskControl) { mods.insert("ctrl") }
        if flags.contains(.maskShift) { mods.insert("shift") }
        if flags.contains(.maskAlternate) { mods.insert("alt") }
        if flags.contains(.maskCommand) { mods.insert("cmd") }
        return mods
    }
}
