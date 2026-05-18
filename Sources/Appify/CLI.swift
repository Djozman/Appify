import Foundation

struct CLIArgs {
    let url: String
    let name: String
    let width: Int
    let height: Int
    let iconPath: String?
    let outputDir: String
    let noFavicon: Bool
    let menuBar: Bool
}

enum CLIError: Error, LocalizedError {
    case missingArguments
    case invalidURL(String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingArguments:
            return "Usage: appify <url> <name> [options]\nRun 'appify --help' for full usage."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .unknownFlag(let flag):
            return "Unknown option: \(flag)\nRun 'appify --help' for full usage."
        }
    }
}

func parseArgs(_ args: [String]) throws -> CLIArgs {
    var positional: [String] = []
    var width = 1280
    var height = 800
    var iconPath: String? = nil
    var outputDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications").path
    var noFavicon = false
    var menuBar = false

    var i = 1
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--width":
            i += 1; width = Int(args[i]) ?? 1280
        case "--height":
            i += 1; height = Int(args[i]) ?? 800
        case "--icon":
            i += 1; iconPath = args[i]
        case "--output":
            i += 1; outputDir = args[i]
        case "--no-favicon":
            noFavicon = true
        case "--menu-bar":
            menuBar = true
        case "--help", "-h":
            printHelp(); exit(0)
        case "--version":
            print("appify v1.0.0"); exit(0)
        default:
            if arg.hasPrefix("--") {
                throw CLIError.unknownFlag(arg)
            }
            positional.append(arg)
        }
        i += 1
    }

    guard positional.count >= 2 else { throw CLIError.missingArguments }

    var url = positional[0]
    if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
        url = "https://" + url
    }
    guard URL(string: url) != nil else { throw CLIError.invalidURL(url) }

    return CLIArgs(
        url: url,
        name: positional[1],
        width: width,
        height: height,
        iconPath: iconPath,
        outputDir: outputDir,
        noFavicon: noFavicon,
        menuBar: menuBar
    )
}

func printHelp() {
    print("""
    appify — Turn any website into a macOS .app

    Usage:
      appify <url> <name> [options]

    Arguments:
      url       Website URL  (e.g. https://monochrome.tf)
      name      App name     (e.g. Monochrome)

    Options:
      --width   <int>   Default window width  (default: 1280)
      --height  <int>   Default window height (default: 800)
      --icon    <path>  Path to .png or .icns icon file
      --output  <path>  Output directory      (default: ~/Applications)
      --no-favicon      Skip auto-fetching the site favicon
      --menu-bar        Run as menu bar app (no Dock icon)
      --version         Print version and exit
      --help, -h        Show this message

    Examples:
      appify https://monochrome.tf "Monochrome"
      appify https://notion.so "Notion" --width 1200 --height 900
      appify https://reddit.com "Reddit" --icon ~/reddit.png
      appify https://linear.app "Linear" --menu-bar
    """)
}
