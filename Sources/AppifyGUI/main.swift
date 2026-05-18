import Cocoa
import AppifyCore

let app = NSApplication.shared
app.setActivationPolicy(.regular)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { self.run() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func run() {
        guard let setup = runSetupUI(url: "", name: "") else { NSApp.terminate(nil); return }
        guard !setup.cancelled else { NSApp.terminate(nil); return }

        guard let launcherBinary = launcherBinaryURL() else {
            showError("Launcher binary not found. Please reinstall Appify.")
            return
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var iconURL: URL? = nil
        if let customIcon = setup.iconPath {
            // User picked a custom icon
            let iconPath = URL(fileURLWithPath: customIcon)
            if iconPath.pathExtension.lowercased() == "icns" {
                iconURL = iconPath
            } else {
                iconURL = IconConverter.convertPngToIcns(pngPath: iconPath, tempDir: tempDir)
            }
        } else if let png = setup.previewPNG {
            // Use the exact PNG already shown in the preview — no re-fetch, no white card
            let pngPath = tempDir.appendingPathComponent("icon_preview.png")
            if (try? png.write(to: pngPath)) != nil {
                iconURL = IconConverter.buildIcnsFromPNG(pngPath: pngPath, tempDir: tempDir)
            }
        }

        let args = CLIArgs(
            url: setup.url,
            name: setup.name,
            width: setup.width,
            height: setup.height,
            iconPath: setup.iconPath,
            outputDir: setup.outputDir,
            noFavicon: setup.iconPath != nil,
            menuBar: setup.menuBar
        )

        do {
            let builder = BundleBuilder(args: args, launcherBinary: launcherBinary)
            let appURL = try builder.build(iconURL: iconURL)
            try? fm.removeItem(at: tempDir)
            showSuccess(appURL: appURL)
        } catch {
            try? fm.removeItem(at: tempDir)
            showError(error.localizedDescription)
        }
    }

    func showSuccess(appURL: URL) {
        let alert = NSAlert()
        alert.messageText = "App created!"
        alert.informativeText = "\(appURL.lastPathComponent) was added to your Applications folder."
        alert.addButton(withTitle: "Launch App")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Done")
        alert.alertStyle = .informational
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        default: break
        }
        let again = NSAlert()
        again.messageText = "Create another app?"
        again.addButton(withTitle: "Create Another")
        again.addButton(withTitle: "Quit")
        if again.runModal() == .alertFirstButtonReturn {
            run()
        } else {
            NSApp.terminate(nil)
        }
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Appify Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
