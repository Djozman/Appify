import AppifyCore
import Cocoa

/// The shared application is an AppifyApplication (see Info.plist
/// NSPrincipalClass), so terminate: goes through our override that
/// stops modal sessions first.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

// ── DEBUG: log every quit attempt ─────────────────────────────────────
func logQuit(_ source: String) {
    let msg = "\(Date()): QUIT from \(source)\n"
    if let data = msg.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/appify_quit.log"))
        {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/appify_quit.log"))
        }
    }
}

logQuit("startup")

// ── Quit observer (backup) ────────────────────────────────────────────
NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification,
    object: nil, queue: .main
) { _ in
    logQuit("willTerminateNotification")
    exit(0)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    @objc func handleQuitEvent(
        _ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor
    ) {
        logQuit("AppleEvent-Quit")
        // Go through NSApp.terminate: so our custom AppifyApplication
        // override stops modal sessions first.
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logQuit("applicationDidFinishLaunching")

        // Cmd+Q key monitor — catches the key event even during modal
        // sessions (local monitors work in all run loop modes).
        // We use exit(0) directly here rather than NSApp.terminate:
        // because terminate: can get queued during modal sessions.
        // exit(0) terminates the process immediately regardless.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers?.lowercased() == "q"
            {
                logQuit("keyMonitor-CmdQ")
                exit(0)
            }
            return event
        }

        // Register a direct Apple Event handler for Quit as a backup.
        // In most cases NSApplication handles kAEQuitApplication internally,
        // but this provides a safety net.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleQuitEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEQuitApplication))
        logQuit("AppleEvent-registered")

        // Ensure there's a main menu — the Dock uses it to validate Quit.
        if NSApp.mainMenu == nil {
            let mainMenu = NSMenu()
            let appMenu = NSMenu(title: "Appify")
            appMenu.addItem(
                NSMenuItem(
                    title: "Quit Appify", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q"))
            let appMenuItem = NSMenuItem()
            appMenuItem.submenu = appMenu
            mainMenu.addItem(appMenuItem)
            NSApp.mainMenu = mainMenu
        }

        DispatchQueue.main.async { self.run() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        logQuit("applicationShouldTerminateAfterLastWindowClosed")
        // Return false because the setup window is closed when the user
        // clicks "Create" — we don't want that to terminate the app.
        // The app manages its own lifecycle via the "Create Another?"
        // dialog and explicit Quit actions.
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        logQuit("applicationShouldTerminate")
        return .terminateNow
    }

    func run() {
        guard let setup = runSetupUI(url: "", name: "") else {
            NSApp.terminate(nil)
            return
        }
        guard !setup.cancelled else {
            NSApp.terminate(nil)
            return
        }

        guard let launcherBinary = launcherBinaryURL() else {
            showError("Launcher binary not found. Please reinstall Appify.")
            return
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var iconURL: URL? = nil
        if let customIcon = setup.iconPath {
            let iconPath = URL(fileURLWithPath: customIcon)
            if iconPath.pathExtension.lowercased() == "icns" {
                iconURL = iconPath
            } else {
                iconURL = IconConverter.convertPngToIcns(pngPath: iconPath, tempDir: tempDir)
            }
        } else if let png = setup.previewPNG {
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
            useBrowser: setup.useBrowser
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
            NSWorkspace.shared.openApplication(
                at: appURL, configuration: NSWorkspace.OpenConfiguration())
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
