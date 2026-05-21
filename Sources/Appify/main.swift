import AppifyCore
import Cocoa
import Foundation

// CLI entry point
do {
    let args = try parseArgs(CommandLine.arguments)
    try runCLI(args: args)
} catch {
    fputs("ERROR: \(error.localizedDescription)\n", stderr)
    exit(1)
}

func runCLI(args: CLIArgs) throws {
    guard let setup = runSetupUI(url: args.url, name: args.name) else {
        fputs("UI failed to launch.\n", stderr)
        exit(1)
    }
    guard !setup.cancelled else {
        print("Cancelled.")
        exit(0)
    }

    print("")
    print("  Appify v1.0.0")
    print("  ---------------------------------")
    print("  App   : \(setup.name)")
    print("  URL   : \(setup.url)")
    print("  Size  : \(setup.width)x\(setup.height)")
    print("  Output: \(setup.outputDir)")
    print("")

    guard let launcherBinary = launcherBinaryURL() else {
        throw NSError(
            domain: "Appify", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Launcher binary not found. Run './Scripts/install.sh' to rebuild."
            ])
    }

    let fm = FileManager.default
    try fm.createDirectory(atPath: setup.outputDir, withIntermediateDirectories: true)
    let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

    var iconURL: URL? = nil
    if let customIcon = setup.iconPath {
        let iconPath = URL(fileURLWithPath: customIcon)
        if iconPath.pathExtension.lowercased() == "icns" {
            iconURL = iconPath
        } else {
            print("  Converting custom icon...")
            iconURL = IconConverter.convertPngToIcns(pngPath: iconPath, tempDir: tempDir)
        }
    } else {
        print("  Fetching icon...")
        if let (data, source) = FaviconFetcher.fetchWithSource(from: setup.url) {
            print("  Fetched \(data.count) bytes from: \(source)")
            iconURL = IconConverter.convertToIcns(pngData: data, in: tempDir)
            print(
                iconURL != nil ? "  Icon ready." : "  Conversion failed, continuing without icon.")
        }
    }

    print("  Building .app bundle...")
    let finalArgs = CLIArgs(
        url: setup.url, name: setup.name, width: setup.width,
        height: setup.height, iconPath: setup.iconPath,
        outputDir: setup.outputDir, noFavicon: setup.iconPath != nil,
        useBrowser: setup.useBrowser
    )
    let builder = BundleBuilder(args: finalArgs, launcherBinary: launcherBinary)
    let appURL = try builder.build(iconURL: iconURL)
    try? fm.removeItem(at: tempDir)

    print("")
    print("  Created: \(appURL.path)")
    print("")
    print("  Launching...")
    Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [appURL.path])
}
