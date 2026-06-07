import Cocoa
import AppKit

/// 系统通知（使用 NSUserNotificationCenter，显示 app 自己的图标）
struct ClipboardHelper {

    static func notify(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message

        let center = NSUserNotificationCenter.default
        center.delegate = NotificationDelegate.shared
        center.deliver(notification)
    }
}

private class NotificationDelegate: NSObject, NSUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
}
