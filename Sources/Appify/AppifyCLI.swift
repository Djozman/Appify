import Foundation
import Cocoa

@main
struct AppifyCLI {
    static func main() {
        do {
            let cliArgs = try parseArgs(CommandLine.arguments)
            try run(args: cliArgs)
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run(args: CLIArgs) throws {
        guard let setup = runSetupUI(url: args.url, name: args.name) else {
            fputs("UI failed to launch.\n", stderr)
            exit(1)
        }
        guard !setup.cancelled else { print("Cancelled."); exit(0) }

        print("")
        print("  Appify v1.2.0")
        print("  ---------------------------------")
        print("  App   : \(setup.name)")
        print("  URL   : \(setup.url)")
        print("  Size  : \(setup.width)x\(setup.height)")
        if setup.menuBar { print("  Mode  : Menu bar") }
        print("  Output: \(setup.outputDir)")
        print("")

        guard let launcherBinary = Bundle.module.url(forResource: "Resources/Launcher", withExtension: nil) else {
            throw AppifyError.launcherNotFound
        }

        let fm = FileManager.default
        try fm.createDirectory(atPath: setup.outputDir, withIntermediateDirectories: true)

        var iconURL: URL? = nil

        if let customIcon = setup.iconPath {
            let iconPath = URL(fileURLWithPath: customIcon)
            if iconPath.pathExtension.lowercased() == "icns" {
                iconURL = iconPath
            } else {
                print("  Converting custom icon to .icns...")
                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: tempDir) }
                iconURL = IconConverter.convertPngToIcns(pngPath: iconPath, tempDir: tempDir)
                print(iconURL != nil ? "  Icon converted." : "  Icon conversion failed.")
            }
        } else {
            print("  Fetching icon for \(setup.url)...")
            if let (data, source) = FaviconFetcher.fetchWithSource(from: setup.url) {
                print("  Fetched \(data.count) bytes from: \(source)")
                let header = data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                print("  Magic bytes: \(header)")

                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: tempDir) }

                print("  Converting to .icns...")
                iconURL = IconConverter.convertToIcns(pngData: data, in: tempDir)
                print(iconURL != nil ? "  Icon ready." : "  Conversion returned nil — check magic bytes above.")
            } else {
                print("  Fetch returned nil — all candidates failed.")
            }
        }

        print("  Building .app bundle...")

        let finalArgs = CLIArgs(
            url: setup.url,
            name: setup.name,
            width: setup.width,
            height: setup.height,
            iconPath: setup.iconPath,
            outputDir: setup.outputDir,
            noFavicon: setup.iconPath != nil,
            menuBar: setup.menuBar
        )

        let builder = BundleBuilder(args: finalArgs, launcherBinary: launcherBinary)
        let appURL = try builder.build(iconURL: iconURL)

        print("")
        print("  Created: \(appURL.path)")
        print("")
        print("  Launching...")
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [appURL.path])
    }
}

enum AppifyError: Error, LocalizedError {
    case launcherNotFound
    var errorDescription: String? { "Launcher binary not found. Run './Scripts/install.sh' to rebuild." }
}
