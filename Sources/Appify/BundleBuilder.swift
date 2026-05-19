import CryptoKit
import Foundation

struct BundleBuilder {
    let args: CLIArgs
    let launcherBinary: URL

    func build(iconURL: URL?) throws -> URL {
        let fm = FileManager.default
        let outputDir = URL(fileURLWithPath: args.outputDir)
        let appURL = outputDir.appendingPathComponent("\(args.name).app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        if fm.fileExists(atPath: appURL.path) {
            try fm.removeItem(at: appURL)
        }
        for dir in [macosURL, resourcesURL] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Copy the native launcher binary directly — no bash wrapper.
        // CFBundleExecutable points right to this, so Apple Events (Quit,
        // Dock click) are delivered straight to our NSApplication.
        let binaryDest = macosURL.appendingPathComponent("launcher")
        try fm.copyItem(at: launcherBinary, to: binaryDest)
        try setExecutable(at: binaryDest)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: buildPlist(hasIcon: iconURL != nil),
            format: .xml, options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        try "APPL????".write(
            to: contentsURL.appendingPathComponent("PkgInfo"),
            atomically: true, encoding: .utf8
        )

        if let iconURL = iconURL, fm.fileExists(atPath: iconURL.path) {
            try fm.copyItem(at: iconURL, to: resourcesURL.appendingPathComponent("icon.icns"))
        }

        return appURL
    }

    private func buildPlist(hasIcon: Bool) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleName": args.name,
            "CFBundleDisplayName": args.name,
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": "com.appify.\(sanitizeBundleId(args.name)).\(urlHash)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.1",
            "CFBundleVersion": "2",
            "NSHighResolutionCapable": true,
            "LSMinimumSystemVersion": "13.0",
            "NSPrincipalClass": "NSApplication",
            "NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true],
            // Custom keys read by the Launcher at startup
            "AppifyURL": args.url,
            "AppifyWidth": args.width,
            "AppifyHeight": args.height,
            "AppifyBrowser": args.useBrowser,
        ]
        if hasIcon { plist["CFBundleIconFile"] = "icon" }
        return plist
    }

    private func sanitizeBundleId(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    /// Returns the first 8 hex characters of the SHA-256 hash of `args.url`.
    /// Deterministic — same URL always produces the same hash.
    private var urlHash: String {
        let digest = SHA256.hash(data: Data(args.url.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private func setExecutable(at url: URL) throws {
        var attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let current = (attrs[.posixPermissions] as? Int) ?? 0o644
        attrs[.posixPermissions] = current | 0o111
        try FileManager.default.setAttributes(attrs, ofItemAtPath: url.path)
    }
}
