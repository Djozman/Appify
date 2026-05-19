import Cocoa
import WebKit

// ── Read config from Info.plist ────────────────────────────────────────
// No bash wrapper, no env vars — we are the native CFBundleExecutable.
// Apple Events (Quit, Dock click) are delivered straight to NSApp.

let plist = Bundle.main.infoDictionary ?? [:]
let appName = plist["CFBundleName"] as? String ?? "App"
let urlString = plist["AppifyURL"] as? String ?? "https://example.com"
let width = plist["AppifyWidth"] as? Int ?? 1280
let height = plist["AppifyHeight"] as? Int ?? 800
let useBrowser = plist["AppifyBrowser"] as? Bool ?? false

// ── Browser-only mode: open URL in app-mode window, then exit ─────────

if useBrowser {
    guard URL(string: urlString) != nil else { exit(1) }
    // Briefly show the app's icon in the Dock so it doesn't look like
    // we're launching the browser directly.
    if let iconURL = Bundle.main.url(forResource: "icon", withExtension: "icns"),
        let icon = NSImage(contentsOf: iconURL)
    {
        NSApp.applicationIconImage = icon
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        openInAppMode(url: urlString)
        exit(0)
    }
    NSApp.run()  // needed so activate() actually shows the icon
}

/// Try each installed browser with its app-mode flag so the user gets a
/// clean, chromeless window. Falls back to the system default browser.
func openInAppMode(url: String) {
    let browsers: [(bundle: String, exe: String, args: [String])] = [
        ("Google Chrome", "Google Chrome", ["--app=\(url)"]),
        ("Microsoft Edge", "Microsoft Edge", ["--app=\(url)"]),
        ("Brave Browser", "Brave Browser", ["--app=\(url)"]),
        ("Firefox", "firefox", ["--new-window", url]),
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
    // Fallback: Safari or system default
    NSWorkspace.shared.open(URL(string: url)!)
}

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

    // Toolbar button references for state updates
    private var backButton: NSButton?
    private var forwardButton: NSButton?
    private var reloadButton: NSButton?

    // KVO context
    private var kvoContext = 0

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

        // Observe navigation state so we can enable/disable toolbar buttons
        wv.addObserver(
            self, forKeyPath: #keyPath(WKWebView.canGoBack),
            options: [], context: &kvoContext)
        wv.addObserver(
            self, forKeyPath: #keyPath(WKWebView.canGoForward),
            options: [], context: &kvoContext)
        wv.addObserver(
            self, forKeyPath: #keyPath(WKWebView.isLoading),
            options: [], context: &kvoContext)
        wv.addObserver(
            self, forKeyPath: #keyPath(WKWebView.url),
            options: [], context: &kvoContext)

        if let url = URL(string: urlString) { wv.load(URLRequest(url: url)) }
        return wv
    }

    // ── KVO ───────────────────────────────────────────────────────────

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard context == &kvoContext else {
            super.observeValue(
                forKeyPath: keyPath, of: object,
                change: change, context: context)
            return
        }
        DispatchQueue.main.async { self.syncToolbarState() }
    }

    private func syncToolbarState() {
        backButton?.isEnabled = webView.canGoBack
        forwardButton?.isEnabled = webView.canGoForward
        if webView.isLoading {
            reloadButton?.image = NSImage(
                systemSymbolName: "xmark",
                accessibilityDescription: "Stop")
            reloadButton?.toolTip = "Stop"
        } else {
            reloadButton?.image = NSImage(
                systemSymbolName: "arrow.clockwise",
                accessibilityDescription: "Reload")
            reloadButton?.toolTip = "Reload"
        }
    }

    // ── Window ────────────────────────────────────────────────────────

    private func openWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [
                .titled, .closable, .miniaturizable, .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        win.title = appName
        win.contentView = webView

        // Minimal toolbar: back · forward · reload · [space] · open in browser
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
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .back:
            let btn = toolbarButton("chevron.left", "Back", #selector(goBack))
            backButton = btn
            item.view = btn
            item.label = "Back"

        case .forward:
            let btn = toolbarButton("chevron.right", "Forward", #selector(goForward))
            forwardButton = btn
            item.view = btn
            item.label = "Forward"

        case .reload:
            let btn = toolbarButton("arrow.clockwise", "Reload", #selector(reloadOrStop))
            reloadButton = btn
            item.view = btn
            item.label = "Reload"

        case .openInSafari:
            let btn = toolbarButton(
                "safari", "Open in browser",
                #selector(openInSafari))
            item.view = btn
            item.label = "Open in browser"

        default:
            return nil
        }
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar)
        -> [NSToolbarItem.Identifier]
    {
        [.back, .forward, .reload, .flexibleSpace, .openInSafari]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar)
        -> [NSToolbarItem.Identifier]
    {
        [.back, .forward, .reload, .flexibleSpace, .openInSafari]
    }

    /// Convenience: create an NSButton wired to an action, suitable for a
    /// toolbar item view.
    private func toolbarButton(
        _ symbolName: String, _ toolTip: String,
        _ action: Selector
    ) -> NSButton {
        let img = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: toolTip)!
        let btn = NSButton(image: img, target: self, action: action)
        btn.bezelStyle = .texturedRounded
        btn.toolTip = toolTip
        return btn
    }

    // ── Toolbar actions ───────────────────────────────────────────────

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func reloadOrStop() {
        if webView.isLoading {
            webView.stopLoading()
        } else {
            webView.reload()
        }
    }

    @objc private func openInSafari() {
        let targetURL = webView.url ?? URL(string: urlString)!
        NSWorkspace.shared.open(targetURL)
    }

    // ── NSWindowDelegate ──────────────────────────────────────────────

    func windowWillClose(_ notification: Notification) {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.isLoading))
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        exit(0)
    }

    // ── NSApplicationDelegate ─────────────────────────────────────────

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            openWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication)
        -> NSApplication.TerminateReply
    {
        webView?.stopLoading()
        exit(0)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApp.setActivationPolicy(.regular)

// ── Edit menu so Cmd+C/V/A/X work in WKWebView ───────────────────────
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
