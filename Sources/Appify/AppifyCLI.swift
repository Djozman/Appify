import Foundation

@main
struct AppifyCLI {
    static func main() {
        do {
            let args = try parseArgs(CommandLine.arguments)
            try run(args: args)
        } catch {
            fputs("✗ \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func run(args: CLIArgs) throws {
        print("")
        print("  Appify v1.1.0")
        print("  ---------------------------------")
        print("  App   : \(args.name)")
        print("  URL   : \(args.url)")
        print("  Size  : \(args.width)x\(args.height)")
        if args.menuBar { print("  Mode  : Menu bar") }
        print("  Output: \(args.outputDir)")
        print("")

        guard let launcherBinary = Bundle.module.url(
            forResource: "Resources/Launcher",
            withExtension: nil
        ) else {
            throw AppifyError.launcherNotFound
        }

        let fm = FileManager.default
        try fm.createDirectory(atPath: args.outputDir, withIntermediateDirectories: true)

        var iconURL: URL? = nil

        if let customIcon = args.iconPath {
            let iconPath = URL(fileURLWithPath: customIcon)
            if iconPath.pathExtension.lowercased() == "icns" {
                iconURL = iconPath
            } else if iconPath.pathExtension.lowercased() == "png" {
                print("  Converting icon to .icns...")
                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: tempDir) }
                iconURL = IconConverter.convertPngToIcns(pngPath: iconPath, tempDir: tempDir)
                print(iconURL != nil ? "  OK Icon converted" : "  WARN Icon conversion failed, continuing without icon")
            }
        } else if !args.noFavicon {
            print("  Fetching favicon...")
            if let data = FaviconFetcher.fetch(from: args.url) {
                print("  Converting to .icns...")
                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: tempDir) }
                iconURL = IconConverter.convertToIcns(pngData: data, in: tempDir)
                print(iconURL != nil ? "  OK Icon ready" : "  WARN Could not convert favicon, continuing without icon")
            } else {
                print("  WARN Could not fetch favicon, continuing without icon")
            }
        }

        print("  Building .app bundle...")
        let builder = BundleBuilder(args: args, launcherBinary: launcherBinary)
        let appURL = try builder.build(iconURL: iconURL)

        print("")
        print("  OK Created: \(appURL.path)")
        print("")
        print("  Launch:")
        print("    open \"\(appURL.path)\"")
        print("")
    }
}

enum AppifyError: Error, LocalizedError {
    case launcherNotFound
    var errorDescription: String? {
        "Launcher binary not found. Run './Scripts/install.sh' to rebuild."
    }
}
