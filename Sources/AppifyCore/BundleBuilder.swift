import Foundation

public struct BundleBuilder {
    public let args: CLIArgs
    public let launcherBinary: URL

    public init(args: CLIArgs, launcherBinary: URL) {
        self.args = args
        self.launcherBinary = launcherBinary
    }

    public func build(iconURL: URL?) throws -> URL {
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

        let binaryDest = macosURL.appendingPathComponent("launcher")
        try fm.copyItem(at: launcherBinary, to: binaryDest)
        try setExecutable(at: binaryDest)

        let wrapperURL = macosURL.appendingPathComponent("run")
        try wrapperScript().write(to: wrapperURL, atomically: true, encoding: .utf8)
        try setExecutable(at: wrapperURL)

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: buildPlist(hasIcon: iconURL != nil),
            format: .xml, options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try "APPL????".write(to: contentsURL.appendingPathComponent("PkgInfo"),
                            atomically: true, encoding: .utf8)

        if let iconURL = iconURL, fm.fileExists(atPath: iconURL.path) {
            try fm.copyItem(at: iconURL, to: resourcesURL.appendingPathComponent("icon.icns"))
        }

        return appURL
    }

    private func wrapperScript() -> String {
        let safeName = args.name.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        #!/bin/bash
        DIR="$(cd "$(dirname "$0")" && pwd)"
        export APPIFY_NAME="\(safeName)"
        export APPIFY_URL="\(args.url)"
        export APPIFY_WIDTH="\(args.width)"
        export APPIFY_HEIGHT="\(args.height)"
        export APPIFY_MENUBAR="\(args.menuBar ? "1" : "0")"
        exec "$DIR/launcher"
        """
    }

    private func buildPlist(hasIcon: Bool) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleName": args.name,
            "CFBundleDisplayName": args.name,
            "CFBundleExecutable": "run",
            "CFBundleIdentifier": "com.appify.\(sanitizeBundleId(args.name))",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "NSHighResolutionCapable": true,
            "LSMinimumSystemVersion": "13.0",
            "NSPrincipalClass": "NSApplication",
            "NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true],
        ]
        if hasIcon { plist["CFBundleIconFile"] = "icon" }
        if args.menuBar { plist["LSUIElement"] = true }
        return plist
    }

    private func sanitizeBundleId(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func setExecutable(at url: URL) throws {
        var attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let current = (attrs[.posixPermissions] as? Int) ?? 0o644
        attrs[.posixPermissions] = current | 0o111
        try FileManager.default.setAttributes(attrs, ofItemAtPath: url.path)
    }
}
