import Foundation

/// Returns the embedded Launcher binary URL.
///
/// We intentionally avoid Bundle.module here — SPM's generated Bundle.module
/// crashes with an assertion failure (SIGTRAP) if the resource bundle exists
/// but doesn't contain the requested file. Instead we look in two safe places:
///
/// 1. Contents/Resources/Launcher  — inside the running Appify.app (distributed app)
/// 2. Next to the executable        — works for `swift run` / dev builds
public func launcherBinaryURL() -> URL? {
    // 1. Distributed app: Contents/Resources/Launcher
    let appBundleLauncher = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Resources/Launcher")
    if FileManager.default.fileExists(atPath: appBundleLauncher.path) {
        return appBundleLauncher
    }

    // 2. Same directory as the running executable (dev / swift run)
    if let execURL = Bundle.main.executableURL {
        let sibling = execURL.deletingLastPathComponent().appendingPathComponent("Launcher")
        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }
    }

    return nil
}
