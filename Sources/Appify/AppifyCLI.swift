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
        print("  Appify v1.0.0")
        print("  ─────────────────────────────────")
        print("  App   : \(args.name)")
        print("  URL   : \(args.url)")
        print("  Size  : \(args.width)×\(args.height)")
        if args.menuBar { print("  Mode  : Menu bar") }
        print("  Output: \(args.outputDir)")
        print("")

        let fm = FileManager.default

        try fm.createDirectory(
            atPath: args.outputDir,
            withIntermediateDirectories: true
        )

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
                print(iconURL != nil ? "  ✓ Icon converted" : "  ⚠ Icon conversion failed, continuing without icon")
            }
        } else if !args.noFavicon {
            print("  Fetching favicon from \(args.url)...")
            if let data = FaviconFetcher.fetch(from: args.url) {
                print("  Converting to .icns...")
                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: tempDir) }
                iconURL = IconConverter.convertToIcns(pngData: data, in: tempDir)
                print(iconURL != nil ? "  ✓ Icon ready" : "  ⚠ Could not convert favicon, continuing without icon")
            } else {
                print("  ⚠ Could not fetch favicon, continuing without icon")
            }
        }

        print("  Building .app bundle...")
        let builder = BundleBuilder(args: args)
        let appURL = try builder.build(iconURL: iconURL)

        print("")
        print("  ✓ Created: \(appURL.path)")
        print("")
        print("  Launch:")
        print("    open \"\(appURL.path)\"")
        print("")
        print("  Requires pywebview:")
        print("    pip install pywebview")
        print("")
    }
}
