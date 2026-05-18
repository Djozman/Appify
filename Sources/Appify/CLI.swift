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
    case missingURL
    case invalidURL(String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Usage: appify <url> [name] [options]\nRun 'appify --help' for full usage."
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
    var outputDir = "/Applications"  // default to system Applications
    var noFavicon = false
    var menuBar = false

    var i = 1
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--width":      i += 1; width = Int(args[i]) ?? 1280
        case "--height":     i += 1; height = Int(args[i]) ?? 800
        case "--icon":       i += 1; iconPath = args[i]
        case "--output":     i += 1; outputDir = args[i]
        case "--no-favicon": noFavicon = true
        case "--menu-bar":   menuBar = true
        case "--help", "-h": printHelp(); exit(0)
        case "--version":    print("appify v1.2.0"); exit(0)
        default:
            if arg.hasPrefix("--") { throw CLIError.unknownFlag(arg) }
            positional.append(arg)
        }
        i += 1
    }

    // URL is required, name is optional (can be set in UI)
    guard !positional.isEmpty else { throw CLIError.missingURL }

    var url = positional[0]
    if !url.hasPrefix("http://") && !url.hasPrefix("https://") { url = "https://" + url }
    guard URL(string: url) != nil else { throw CLIError.invalidURL(url) }

    // Derive default name from hostname
    let defaultName: String
    if positional.count >= 2 {
        defaultName = positional[1]
    } else if let host = URL(string: url)?.host {
        let clean = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        defaultName = clean.components(separatedBy: ".").first?.capitalized ?? clean
    } else {
        defaultName = ""
    }

    return CLIArgs(
        url: url, name: defaultName,
        width: width, height: height,
        iconPath: iconPath, outputDir: outputDir,
        noFavicon: noFavicon, menuBar: menuBar
    )
}

func printHelp() {
    print("""
    appify - Turn any website into a macOS .app

    Usage:
      appify <url> [name] [options]

    Arguments:
      url       Website URL  (e.g. https://monochrome.tf)
      name      App name     (optional, can be set in the UI)

    Options:
      --width   <int>   Default window width  (default: 1280)
      --height  <int>   Default window height (default: 800)
      --icon    <path>  Path to .png or .icns icon file
      --output  <path>  Output directory      (default: /Applications)
      --no-favicon      Skip auto-fetching the site favicon
      --menu-bar        Pre-check menu bar mode in UI
      --version         Print version and exit
      --help, -h        Show this message

    Examples:
      appify https://monochrome.tf
      appify https://notion.so "Notion"
      appify https://linear.app --menu-bar
    """)
}
