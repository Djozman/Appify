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
        win.delegate = self
        // Default isReleasedWhenClosed = true lets the window be deallocated
        // immediately on close, which avoids stale references.
        win.title = appName
        win.contentView = webView
        win.center()
        win.setFrameAutosaveName(appName)
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    // ── NSWindowDelegate ──────────────────────────────────────────────

    /// Clicking the red X quits the app directly — no waiting for
    /// applicationShouldTerminateAfterLastWindowClosed.
    func windowWillClose(_ notification: Notification) {
        if !isMenuBar {
            NSApp.terminate(nil)
        }
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
