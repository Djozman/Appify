import Cocoa
import WebKit

// ── Read config from Info.plist ────────────────────────────────────────
// No bash wrapper, no env vars — we are the native CFBundleExecutable.
// Apple Events (Quit, Dock click) are delivered straight to NSApp.

let plist = Bundle.main.infoDictionary ?? [:]
let appName   = plist["CFBundleName"] as? String ?? "App"
let urlString = plist["AppifyURL"]   as? String ?? "https://example.com"
let width     = plist["AppifyWidth"]  as? Int ?? 1280
let height    = plist["AppifyHeight"] as? Int ?? 800
let isMenuBar = plist["AppifyMenuBar"] as? Bool ?? false

// ── App Delegate ──────────────────────────────────────────────────────

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        webView?.stopLoading()
        exit(0)
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(isMenuBar ? .accessory : .regular)
NSApp.run()
