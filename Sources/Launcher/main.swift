import Cocoa
import WebKit

let appName   = ProcessInfo.processInfo.environment["APPIFY_NAME"]    ?? "App"
let urlString = ProcessInfo.processInfo.environment["APPIFY_URL"]     ?? "https://example.com"
let width     = Int(ProcessInfo.processInfo.environment["APPIFY_WIDTH"]  ?? "1280") ?? 1280
let height    = Int(ProcessInfo.processInfo.environment["APPIFY_HEIGHT"] ?? "800")  ?? 800
let isMenuBar = ProcessInfo.processInfo.environment["APPIFY_MENUBAR"] == "1"

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        webView = makeWebView()
        openWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        if let url = URL(string: urlString) { wv.load(URLRequest(url: url)) }
        return wv
    }

    private func openWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Default isReleasedWhenClosed = true: window is deallocated on close,
        // which lets applicationShouldTerminateAfterLastWindowClosed fire correctly.
        win.title = appName
        win.contentView = webView
        win.center()
        win.setFrameAutosaveName(appName)
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    // Quit when the last window is closed (normal app behaviour).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !isMenuBar
    }

    // Dock icon clicked while no window is visible — reopen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    // Ensure Quit always works — stop the web view so it can't block termination.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        webView?.stopLoading()
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(isMenuBar ? .accessory : .regular)
NSApp.run()
