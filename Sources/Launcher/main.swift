import Cocoa
import WebKit

let appName   = ProcessInfo.processInfo.environment["APPIFY_NAME"]    ?? "App"
let urlString = ProcessInfo.processInfo.environment["APPIFY_URL"]     ?? "https://example.com"
let width     = Int(ProcessInfo.processInfo.environment["APPIFY_WIDTH"]  ?? "1280") ?? 1280
let height    = Int(ProcessInfo.processInfo.environment["APPIFY_HEIGHT"] ?? "800")  ?? 800
let isMenuBar = ProcessInfo.processInfo.environment["APPIFY_MENUBAR"] == "1"

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        win.title = appName
        win.contentView = webView
        win.center()
        win.setFrameAutosaveName(appName)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    // ── NSWindowDelegate ──────────────────────────────────────────────

    /// User clicked the red X — quit the app (unless it's a menu-bar app).
    func windowWillClose(_ notification: Notification) {
        guard !isMenuBar else { return }
        NSApp.terminate(nil)
    }

    // ── NSApplicationDelegate ─────────────────────────────────────────

    // Dock icon clicked while no window is visible — reopen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    /// Stop the web view and force-exit so Quit always works — whether
    /// triggered by the red X, Cmd+Q, or right-click→Quit in the Dock.
    /// NSApp.terminate can get stuck if WKWebView is hogging the run loop,
    /// so we schedule an unconditional exit(0) as a last-resort backup.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exit(0)
        }
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(isMenuBar ? .accessory : .regular)
NSApp.run()
