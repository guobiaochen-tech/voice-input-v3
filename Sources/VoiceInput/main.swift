import AppKit

@MainActor
func startApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

MainActor.assumeIsolated {
    startApp()
}
