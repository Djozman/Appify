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
        // The Appify CLI
        .executableTarget(
            name: "Appify",
            path: "Sources/Appify",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
