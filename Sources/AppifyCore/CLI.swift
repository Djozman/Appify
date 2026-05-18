import Foundation

public struct CLIArgs {
    public let url: String
    public let name: String
    public let width: Int
    public let height: Int
    public let iconPath: String?
    public let outputDir: String
    public let noFavicon: Bool
    public let menuBar: Bool

    public init(url: String, name: String, width: Int, height: Int,
                iconPath: String?, outputDir: String, noFavicon: Bool, menuBar: Bool) {
        self.url = url; self.name = name; self.width = width; self.height = height
        self.iconPath = iconPath; self.outputDir = outputDir
        self.noFavicon = noFavicon; self.menuBar = menuBar
    }
}

public enum CLIError: Error, LocalizedError {
    case missingURL
    case invalidURL(String)
    case unknownFlag(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL:           return "Usage: appify <url> [name] [options]\nRun 'appify --help' for full usage."
        case .invalidURL(let url):  return "Invalid URL: \(url)"
        case .unknownFlag(let f):   return "Unknown option: \(f)\nRun 'appify --help' for full usage."
        }
    }
}

public func parseArgs(_ args: [String]) throws -> CLIArgs {
    var positional: [String] = []
    var width = 1280; var height = 800
    var iconPath: String? = nil
    var outputDir = "/Applications"
    var noFavicon = false; var menuBar = false

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
        case "--version":    print("appify v1.0.0"); exit(0)
        default:
            if arg.hasPrefix("--") { throw CLIError.unknownFlag(arg) }
            positional.append(arg)
        }
        i += 1
    }

    guard !positional.isEmpty else { throw CLIError.missingURL }

    var url = positional[0]
    if !url.hasPrefix("http://") && !url.hasPrefix("https://") { url = "https://" + url }
    guard URL(string: url) != nil else { throw CLIError.invalidURL(url) }

    let defaultName: String
    if positional.count >= 2 {
        defaultName = positional[1]
    } else if let host = URL(string: url)?.host {
        let clean = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        defaultName = clean.components(separatedBy: ".").first?.capitalized ?? clean
    } else {
        defaultName = ""
    }

    return CLIArgs(url: url, name: defaultName, width: width, height: height,
                  iconPath: iconPath, outputDir: outputDir,
                  noFavicon: noFavicon, menuBar: menuBar)
}

public func printHelp() {
    print("""
    appify - Turn any website into a macOS .app

    Usage:
      appify <url> [name] [options]

    Options:
      --width   <int>   Window width  (default: 1280)
      --height  <int>   Window height (default: 800)
      --icon    <path>  Path to .png or .icns icon
      --output  <path>  Output directory (default: /Applications)
      --no-favicon      Skip favicon fetch
      --menu-bar        Menu bar app mode
      --version         Print version
      --help, -h        Show this message
    """)
}
