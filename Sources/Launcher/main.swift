import Cocoa
import WebKit

let appName   = ProcessInfo.processInfo.environment["APPIFY_NAME"]    ?? "App"
let urlString = ProcessInfo.processInfo.environment["APPIFY_URL"]     ?? "https://example.com"
let width     = Int(ProcessInfo.processInfo.environment["APPIFY_WIDTH"]  ?? "1280") ?? 1280
let height    = Int(ProcessInfo.processInfo.environment["APPIFY_HEIGHT"] ?? "800")  ?? 800
let isMenuBar = ProcessInfo.processInfo.environment["APPIFY_MENUBAR"] == "1"

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = appName
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName(appName)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return !isMenuBar
    }

    /// Re-open the window when the Dock icon is clicked while the app is
    /// running but has no visible windows.  Recreates the window if it was
    /// released (e.g. isReleasedWhenClosed was left at the default).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window == nil || window?.isVisible == false {
            if window == nil {
                // Window was released — rebuild it.
                window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                    backing: .buffered,
                    defer: false
                )
                window.isReleasedWhenClosed = false
                window.title = appName
                window.contentView = webView ?? {
                    let config = WKWebViewConfiguration()
                    config.preferences.setValue(true, forKey: "developerExtrasEnabled")
                    let wv = WKWebView(frame: .zero, configuration: config)
                    if let url = URL(string: urlString) { wv.load(URLRequest(url: url)) }
                    webView = wv
                    return wv
                }()
                window.setFrameAutosaveName(appName)
            }
            window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Always allow termination — stop the web view so it cannot block Quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        window?.close()
        return .terminateNow
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(isMenuBar ? .accessory : .regular)
NSApp.run()
