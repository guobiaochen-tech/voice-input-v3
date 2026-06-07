import Cocoa

/// 通过剪贴板粘贴将文本输入到当前光标位置
/// 参考 Typeoff 的 TextInputSimulator.js 实现
struct TextInputService {

    enum TextInputError: LocalizedError {
        case clipboardWriteFailed
        case clipboardVerifyFailed
        case noAccessibilityPermission

        var errorDescription: String? {
            switch self {
            case .clipboardWriteFailed: "剪贴板写入失败"
            case .clipboardVerifyFailed: "剪贴板验证失败"
            case .noAccessibilityPermission: "需要辅助功能权限"
            }
        }
    }

    /// 检查辅助功能权限
    static func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// 通过剪贴板粘贴文本到当前光标位置
    /// 流程：保存剪贴板所有类型 → 写入文本 → 等 30ms 验证 → 模拟 Cmd+V → 等 150ms → 恢复剪贴板
    static func pasteText(_ text: String) throws {
        guard !text.isEmpty else { return }
        guard AXIsProcessTrusted() else { throw TextInputError.noAccessibilityPermission }

        let pb = NSPasteboard.general

        // 1. 保存当前剪贴板所有类型的数据（不只是 string，还有图片、文件、富文本等）
        var savedItems: [[NSPasteboard.PasteboardType: Data]] = []
        if let pasteboardItems = pb.pasteboardItems {
            for item in pasteboardItems {
                var itemData: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        itemData[type] = data
                    }
                }
                if !itemData.isEmpty {
                    savedItems.append(itemData)
                }
            }
        }

        // 2. 写入新文本
        pb.clearContents()
        guard pb.setString(text, forType: .string) else {
            // 写入失败，先恢复剪贴板
            restoreClipboard(pb, savedItems: savedItems)
            throw TextInputError.clipboardWriteFailed
        }

        // 3. 等待 30ms，验证剪贴板内容
        usleep(30_000)
        let verify = pb.string(forType: .string)
        guard verify == text else {
            restoreClipboard(pb, savedItems: savedItems)
            throw TextInputError.clipboardVerifyFailed
        }

        // 4. 模拟 Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }

        // 5. 等待 150ms
        usleep(150_000)

        // 6. 恢复原剪贴板
        restoreClipboard(pb, savedItems: savedItems)
    }

    /// 恢复剪贴板所有保存的类型
    private static func restoreClipboard(_ pb: NSPasteboard, savedItems: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        for itemData in savedItems {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pb.writeObjects([item])
        }
    }
}
