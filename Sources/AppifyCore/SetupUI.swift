import Cocoa
import Foundation

public struct SetupResult {
    public let url: String
    public let name: String
    public let iconPath: String?
    public let previewPNG: Data?
    public let width: Int
    public let height: Int
    public let outputDir: String
    public let menuBar: Bool
    public var cancelled: Bool

    public init(url: String, name: String, iconPath: String?, previewPNG: Data? = nil,
                width: Int, height: Int, outputDir: String, menuBar: Bool, cancelled: Bool = false) {
        self.url = url; self.name = name; self.iconPath = iconPath
        self.previewPNG = previewPNG
        self.width = width; self.height = height
        self.outputDir = outputDir; self.menuBar = menuBar; self.cancelled = cancelled
    }
}

public class SetupWindowController: NSWindowController {
    private let urlField      = NSTextField()
    private let nameField     = NSTextField()
    private let iconImageView = NSImageView()
    private let iconLabel     = NSTextField(labelWithString: "Auto (favicon)")
    private let widthField    = NSTextField()
    private let heightField   = NSTextField()
    private let menuBarCheck  = NSButton(checkboxWithTitle: "Run as menu bar app (no Dock icon)", target: nil, action: nil)
    private var customIconPath: String? = nil
    private var previewPNG: Data? = nil
    private var fetchToken: Int = 0
    public var result: SetupResult?

    public convenience init(url: String, name: String) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Appify — Create App"
        win.center()
        win.level = .floating
        self.init(window: win)
        buildUI(url: url, name: name)
    }

    private func buildUI(url: String, name: String) {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        iconImageView.frame = NSRect(x: 24, y: 260, width: 80, height: 80)
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 16
        iconImageView.layer?.masksToBounds = true
        iconImageView.layer?.borderWidth = 1
        iconImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        iconImageView.image = defaultIcon()
        content.addSubview(iconImageView)

        iconLabel.frame = NSRect(x: 8, y: 240, width: 112, height: 18)
        iconLabel.font = .systemFont(ofSize: 11)
        iconLabel.textColor = .secondaryLabelColor
        iconLabel.alignment = .center
        content.addSubview(iconLabel)

        let chooseBtn = NSButton(title: "Choose Image...", target: self, action: #selector(chooseIcon))
        chooseBtn.frame = NSRect(x: 12, y: 210, width: 104, height: 26)
        chooseBtn.bezelStyle = .rounded
        chooseBtn.font = .systemFont(ofSize: 12)
        content.addSubview(chooseBtn)

        let resetBtn = NSButton(title: "Use Favicon", target: self, action: #selector(resetIcon))
        resetBtn.frame = NSRect(x: 12, y: 182, width: 104, height: 24)
        resetBtn.bezelStyle = .rounded
        resetBtn.font = .systemFont(ofSize: 11)
        resetBtn.toolTip = "Revert to auto-fetched favicon from the URL"
        content.addSubview(resetBtn)

        let rightX: CGFloat = 140; let fieldW: CGFloat = 316

        addLabel("Website URL", x: rightX, y: 356, w: fieldW, to: content)
        urlField.frame = NSRect(x: rightX, y: 332, width: fieldW, height: 22)
        urlField.stringValue = url
        urlField.placeholderString = "https://example.com"
        urlField.target = self
        urlField.action = #selector(urlChanged)
        (urlField.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        content.addSubview(urlField)

        addLabel("App Name", x: rightX, y: 308, w: fieldW, to: content)
        nameField.frame = NSRect(x: rightX, y: 284, width: fieldW, height: 22)
        nameField.stringValue = name
        nameField.placeholderString = "My App"
        content.addSubview(nameField)

        addLabel("Window Size", x: rightX, y: 260, w: 120, to: content)
        widthField.frame = NSRect(x: rightX, y: 236, width: 70, height: 22)
        widthField.stringValue = "1280"
        widthField.placeholderString = "Width"
        content.addSubview(widthField)

        let xLabel = NSTextField(labelWithString: "x")
        xLabel.frame = NSRect(x: rightX + 76, y: 238, width: 14, height: 18)
        content.addSubview(xLabel)

        heightField.frame = NSRect(x: rightX + 96, y: 236, width: 70, height: 22)
        heightField.stringValue = "800"
        heightField.placeholderString = "Height"
        content.addSubview(heightField)

        menuBarCheck.frame = NSRect(x: rightX, y: 200, width: fieldW, height: 22)
        content.addSubview(menuBarCheck)

        let divider = NSBox(); divider.boxType = .separator
        divider.frame = NSRect(x: 20, y: 60, width: 440, height: 1)
        content.addSubview(divider)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.frame = NSRect(x: 296, y: 20, width: 80, height: 32)
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = String(UnicodeScalar(27)!)
        content.addSubview(cancelBtn)

        let createBtn = NSButton(title: "Create App", target: self, action: #selector(create))
        createBtn.frame = NSRect(x: 384, y: 20, width: 80, height: 32)
        createBtn.bezelStyle = .rounded
        createBtn.keyEquivalent = "\r"
        content.addSubview(createBtn)

        if !url.isEmpty {
            iconLabel.stringValue = "Fetching..."
            scheduleFaviconFetch(for: url, debounce: false)
        }
    }

    @discardableResult
    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, to view: NSView) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.frame = NSRect(x: x, y: y, width: w, height: 18)
        lbl.font = .systemFont(ofSize: 12, weight: .medium)
        view.addSubview(lbl)
        return lbl
    }

    private func updateUI(_ block: @escaping () -> Void) {
        let rl = CFRunLoopGetMain()
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    /// Pure CoreGraphics — thread-safe.
    /// White card, favicon scaled to 80% fill, centered.
    private static func compositePNG(faviconData: Data, pixels: Int) -> Data? {
        guard let src = CGImageSourceCreateWithData(faviconData as CFData, nil),
              let cgSrc = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let size = pixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // White background (matches macOS icon card look)
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

        // Scale favicon to 80% of canvas, centered
        let srcW = CGFloat(cgSrc.width)
        let srcH = CGFloat(cgSrc.height)
        let maxSide = CGFloat(size) * 0.80
        let scale = min(maxSide / max(srcW, 1), maxSide / max(srcH, 1))
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawX = (CGFloat(size) - drawW) / 2
        let drawY = (CGFloat(size) - drawH) / 2

        // CG origin is bottom-left; flip to draw image right-side up
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgSrc, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        ctx.restoreGState()

        guard let rendered = ctx.makeImage() else { return nil }
        let dest = NSMutableData()
        guard let imgDest = CGImageDestinationCreateWithData(dest, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(imgDest, rendered, nil)
        guard CGImageDestinationFinalize(imgDest) else { return nil }
        return dest as Data
    }

    private func scheduleFaviconFetch(for urlString: String, debounce: Bool = true) {
        fetchToken &+= 1
        let token = fetchToken
        let delay = debounce ? 0.6 : 0.0
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.fetchToken == token else { return }
            guard let (faviconData, _) = FaviconFetcher.fetchWithSource(from: urlString) else {
                self.updateUI { [weak self] in
                    guard let self, self.fetchToken == token else { return }
                    if self.iconLabel.stringValue == "Fetching..." {
                        self.iconImageView.image = self.defaultIcon()
                        self.iconLabel.stringValue = "No favicon found"
                    }
                }
                return
            }
            // Composite once — used for both preview and icns
            let png1024 = Self.compositePNG(faviconData: faviconData, pixels: 1024)
            self.updateUI { [weak self] in
                guard let self, self.fetchToken == token else { return }
                self.previewPNG = png1024
                guard self.iconLabel.stringValue == "Fetching...", self.customIconPath == nil else { return }
                let previewImg = png1024.flatMap { NSImage(data: $0) }
                    ?? NSImage(data: faviconData)
                if let img = previewImg {
                    self.iconImageView.image = img
                    self.iconLabel.stringValue = "Auto (favicon)"
                } else {
                    self.iconImageView.image = self.defaultIcon()
                    self.iconLabel.stringValue = "No favicon found"
                }
            }
        }
    }

    @objc private func urlChanged() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let url = raw.hasPrefix("http") ? raw : "https://" + raw
        if nameField.stringValue.isEmpty, let host = URL(string: url)?.host {
            let cleaned = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            nameField.stringValue = cleaned.components(separatedBy: ".").first?.capitalized ?? cleaned
        }
        iconLabel.stringValue = "Fetching..."
        scheduleFaviconFetch(for: url, debounce: true)
    }

    @objc private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .icns, .tiff]
        panel.title = "Choose App Icon"
        panel.prompt = "Use as Icon"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customIconPath = url.path
            previewPNG = nil
            if let img = NSImage(contentsOf: url) {
                iconImageView.image = img
                iconLabel.stringValue = url.lastPathComponent
            }
        }
    }

    @objc private func resetIcon() {
        customIconPath = nil
        previewPNG = nil
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            iconImageView.image = defaultIcon()
            iconLabel.stringValue = "Auto (default)"
            return
        }
        iconLabel.stringValue = "Fetching..."
        let resolved = raw.hasPrefix("http") ? raw : "https://" + raw
        scheduleFaviconFetch(for: resolved, debounce: false)
    }

    private func defaultIcon() -> NSImage {
        let size = NSSize(width: 80, height: 80)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 16, yRadius: 16).fill()
        NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .draw(in: NSRect(x: 16, y: 16, width: 48, height: 48))
        img.unlockFocus()
        return img
    }

    @objc private func cancel() {
        result = SetupResult(url: "", name: "", iconPath: nil, previewPNG: nil,
                             width: 1280, height: 800, outputDir: "/Applications",
                             menuBar: false, cancelled: true)
        NSApp.stopModal()
        window?.close()
    }

    @objc private func create() {
        var url = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        if !url.hasPrefix("http") { url = "https://" + url }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !name.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Missing Info"
            alert.informativeText = "Please enter both a URL and an app name."
            alert.runModal()
            return
        }
        result = SetupResult(
            url: url, name: name,
            iconPath: customIconPath,
            previewPNG: customIconPath == nil ? previewPNG : nil,
            width: Int(widthField.stringValue) ?? 1280,
            height: Int(heightField.stringValue) ?? 800,
            outputDir: "/Applications",
            menuBar: menuBarCheck.state == .on
        )
        NSApp.stopModal()
        window?.close()
    }
}

public func runSetupUI(url: String, name: String) -> SetupResult? {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {}
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.finishLaunching()
    let wc = SetupWindowController(url: url, name: name)
    wc.showWindow(nil)
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        wc.window?.makeKeyAndOrderFront(nil)
        wc.window?.orderFrontRegardless()
    }
    app.runModal(for: wc.window!)
    return wc.result
}
