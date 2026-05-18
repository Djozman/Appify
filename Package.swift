// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Appify",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // Tiny native WKWebView app — gets embedded into every .app Appify creates
        .executableTarget(
            name: "Launcher",
            path: "Sources/Launcher"
        ),
        // Shared library: all logic except entry points
        .target(
            name: "AppifyCore",
            path: "Sources/AppifyCore",
            resources: [
                .copy("Resources")
            ]
        ),
        // CLI: appify <url>
        .executableTarget(
            name: "Appify",
            dependencies: ["AppifyCore"],
            path: "Sources/Appify"
        ),
        // GUI: double-click .app
        .executableTarget(
            name: "AppifyGUI",
            dependencies: ["AppifyCore"],
            path: "Sources/AppifyGUI"
        )
    ]
)
