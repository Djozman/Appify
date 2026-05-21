import Foundation

// CLIArgs, parseArgs, and CLIError come from AppifyCore.
// This file only provides printHelp (used by main.swift).

func printHelp() {
    print(
        """
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
          --version         Print version and exit
          --help, -h        Show this message

        Examples:
          appify https://monochrome.tf
          appify https://notion.so "Notion"
        """)
}
