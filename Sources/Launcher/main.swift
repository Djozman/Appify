import Cocoa
import WebKit

let plist = Bundle.main.infoDictionary ?? [:]
let appName = plist["CFBundleName"] as? String ?? "App"
let urlString = plist["AppifyURL"] as? String ?? "https://example.com"
let width = plist["AppifyWidth"] as? Int ?? 1280
let height = plist["AppifyHeight"] as? Int ?? 800
let useBrowser = plist["AppifyBrowser"] as? Bool ?? false

extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("back")
    static let forward = NSToolbarItem.Identifier("forward")
    static let reload = NSToolbarItem.Identifier("reload")
    static let openInSafari = NSToolbarItem.Identifier("openInSafari")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate {
    var window: NSWindow?
    var webView: WKWebView!
    private var backButton: NSButton?
    private var forwardButton: NSButton?
    private var reloadButton: NSButton?
    private var kvoContext = 0
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers?.lowercased() == "q"
            {
                self.killChromeWindow()
                exit(0)
            }
            return event
        }

        if useBrowser {
            if let url = URL(string: urlString) {
                let urlStr = url.absoluteString
                let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
                if FileManager.default.fileExists(atPath: chromePath) {
                    let task = Process()
                    task.launchPath = chromePath
                    task.arguments = ["--app=\(urlStr)"]
                    task.launch()
                    // Capture the Chrome window ID so we only close this one.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.chromeWindowID = self.getChromeWindowID(url: urlStr)
                    }
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        webView = makeWebView()
        openWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var chromeWindowID: String?  // track exact Chrome window

    private func getChromeWindowID(url: String) -> String? {
        let src =
            "tell application \"Google Chrome\" to get id of (first window whose URL of active tab starts with \"\(url)\")"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", src]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func killChromeWindow() {
        guard let id = chromeWindowID else { return }
        let src = "tell application \"Google Chrome\" to close window id \(id)"
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", src]
        task.launch()
    }

    // ── WKWebView ────────────────────────────────────────────────────

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        wv.addObserver(
            self, forKeyPath: #keyPath(WKWebView.canGoBack), options: [], context: &kvoContext)
        wv.addObserver(
            self, forKeyPath: #keyPath(WKWebView.canGoForward), options: [], context: &kvoContext)
        wv.addObserver(
            self, forKeyPath: #keyPath(WKWebView.isLoading), options: [], context: &kvoContext)
        wv.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: [], context: &kvoContext)
        if let url = URL(string: urlString) { wv.load(URLRequest(url: url)) }
        return wv
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?,
        change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        guard context == &kvoContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        DispatchQueue.main.async { self.syncToolbarState() }
    }

    private func syncToolbarState() {
        backButton?.isEnabled = webView.canGoBack
        forwardButton?.isEnabled = webView.canGoForward
        reloadButton?.image =
            webView.isLoading
            ? NSImage(systemSymbolName: "xmark", accessibilityDescription: "Stop")
            : NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
        reloadButton?.toolTip = webView.isLoading ? "Stop" : "Reload"
    }

    private func openWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = appName
        win.contentView = webView
        let toolbar = NSToolbar(identifier: "AppifyToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = true
        win.toolbar = toolbar
        win.toolbarStyle = .unified
        win.center()
        win.setFrameAutosaveName(appName)
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        window = win
        syncToolbarState()
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case .back:
            backButton = toolbarButton("chevron.left", "Back", #selector(goBack))
            item.view = backButton
        case .forward:
            forwardButton = toolbarButton("chevron.right", "Forward", #selector(goForward))
            item.view = forwardButton
        case .reload:
            reloadButton = toolbarButton("arrow.clockwise", "Reload", #selector(reloadOrStop))
            item.view = reloadButton
        case .openInSafari:
            item.view = toolbarButton("safari", "Open in browser", #selector(openInSafari))
        default: return nil
        }
        item.label = id.rawValue
        return item
    }

    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .reload, .flexibleSpace, .openInSafari]
    }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .reload, .flexibleSpace, .openInSafari]
    }

    private func toolbarButton(_ s: String, _ tip: String, _ a: Selector) -> NSButton {
        let b = NSButton(
            image: NSImage(systemSymbolName: s, accessibilityDescription: tip)!, target: self,
            action: a)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        return b
    }

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }
    @objc private func openInSafari() {
        NSWorkspace.shared.open(
            webView.url ?? URL(string: urlString) ?? URL(string: "https://example.com")!)
    }

    func windowWillClose(_ notification: Notification) {
        killChromeWindow()
        if useBrowser { return }
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.isLoading))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        exit(0)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if useBrowser {
            if let id = chromeWindowID {
                // Activate Chrome and bring the specific window to front.
                // Using NSRunningApplication is more direct than AppleScript.
                let chromeApps = NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.google.Chrome")
                if let chrome = chromeApps.first {
                    chrome.activate(options: .activateIgnoringOtherApps)
                }
                // Also tell Chrome via AppleScript to focus the window
                let task = Process()
                task.launchPath = "/usr/bin/osascript"
                task.arguments = [
                    "-e", "tell application \"Google Chrome\" to set index of window id \(id) to 1",
                ]
                task.launch()
            } else if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } else if !flag {
            openWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        killChromeWindow()
        webView?.stopLoading()
        exit(0)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(.regular)

let mainMenu = NSMenu()
let appMenu = NSMenu(title: appName)
appMenu.addItem(
    NSMenuItem(
        title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
    ))
let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(
    NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(
    NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)
NSApp.mainMenu = mainMenu

NSApp.run()
