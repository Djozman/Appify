import Cocoa
import WebKit

// ── Read config from Info.plist ────────────────────────────────────────

let plist = Bundle.main.infoDictionary ?? [:]
let appName = plist["CFBundleName"] as? String ?? "App"
let urlString = plist["AppifyURL"] as? String ?? "https://example.com"
let width = plist["AppifyWidth"] as? Int ?? 1280
let height = plist["AppifyHeight"] as? Int ?? 800
let useBrowser = plist["AppifyBrowser"] as? Bool ?? false

// ── Toolbar item identifiers ──────────────────────────────────────────

extension NSToolbarItem.Identifier {
    static let back = NSToolbarItem.Identifier("back")
    static let forward = NSToolbarItem.Identifier("forward")
    static let reload = NSToolbarItem.Identifier("reload")
    static let openInSafari = NSToolbarItem.Identifier("openInSafari")
}

// ── App Delegate ──────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
    NSToolbarDelegate
{
    var window: NSWindow?
    var webView: WKWebView!

    private var backButton: NSButton?
    private var forwardButton: NSButton?
    private var reloadButton: NSButton?
    private var kvoContext = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if useBrowser {
            // Open in default browser and quit — but first show the
            // app's icon in the Dock briefly so it doesn't look like
            // we're just launching the browser.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let url = URL(string: urlString) {
                    self.openInBrowser(url: url)
                }
                exit(0)
            }
            return
        }
        webView = makeWebView()
        openWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    // ── Browser launcher ─────────────────────────────────────────────

    private func openInBrowser(url: URL) {
        let urlStr = url.absoluteString
        let browsers: [(bundle: String, exe: String, args: [String])] = [
            ("Google Chrome", "Google Chrome", ["--app=\(urlStr)"]),
            ("Microsoft Edge", "Microsoft Edge", ["--app=\(urlStr)"]),
            ("Brave Browser", "Brave Browser", ["--app=\(urlStr)"]),
            ("Firefox", "firefox", ["--new-window", urlStr]),
        ]
        for (bundle, exe, args) in browsers {
            let path = "/Applications/\(bundle).app/Contents/MacOS/\(exe)"
            if FileManager.default.fileExists(atPath: path) {
                let task = Process()
                task.launchPath = path
                task.arguments = args
                task.launch()
                return
            }
        }
        NSWorkspace.shared.open(url)
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

    // ── Window ────────────────────────────────────────────────────────

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

    // ── NSToolbarDelegate ─────────────────────────────────────────────

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

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .reload, .flexibleSpace, .openInSafari]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.back, .forward, .reload, .flexibleSpace, .openInSafari]
    }

    private func toolbarButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let btn = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!,
            target: self, action: action)
        btn.bezelStyle = .texturedRounded
        btn.toolTip = tip
        return btn
    }

    // ── Toolbar actions ───────────────────────────────────────────────

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }
    @objc private func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }
    @objc private func openInSafari() {
        NSWorkspace.shared.open(
            webView.url ?? URL(string: urlString) ?? URL(string: "https://example.com")!)
    }

    // ── NSWindowDelegate ──────────────────────────────────────────────

    func windowWillClose(_ notification: Notification) {
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.isLoading))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        exit(0)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if !flag {
            openWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        webView?.stopLoading()
        exit(0)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(.regular)

// Edit menu for Cmd+C/V/A/X
let mainMenu = NSMenu()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(
    NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(
    NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
let editMenuItem = NSMenuItem()
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)
NSApp.mainMenu = mainMenu

NSApp.run()
