import Foundation

/// Public accessor so AppifyGUI (and the CLI) can reach the embedded Launcher
/// binary without touching Bundle.module directly (which is internal-only).
public func launcherBinaryURL() -> URL? {
    Bundle.module.url(forResource: "Resources/Launcher", withExtension: nil)
}
