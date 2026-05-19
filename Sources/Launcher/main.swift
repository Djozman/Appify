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

    /// Red X → kill process.  NSApp.terminate gets stalled by WKWebView's
    /// run loop; exit(0) is instant — same logic as Cancel's stopModal().
    func windowWillClose(_ notification: Notification) {
        guard !isMenuBar else { return }
        exit(0)
    }

    // ── NSApplicationDelegate ─────────────────────────────────────────

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    /// Cmd+Q / Dock→Quit — kill process immediately.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        webView?.stopLoading()
        exit(0)
        return .terminateNow  // unreachable, keeps compiler happy
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(isMenuBar ? .accessory : .regular)
NSApp.run()
