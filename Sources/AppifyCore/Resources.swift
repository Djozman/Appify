import Foundation

/// Returns the embedded Launcher binary URL.
/// Primary:  Bundle.module (SPM bakes it in at compile-time via AppifyCore/Resources/Launcher)
/// Fallback: Contents/Resources/Launcher inside the running .app bundle
public func launcherBinaryURL() -> URL? {
    // SPM bundle — works when run via `swift run` or during development
    if let url = Bundle.module.url(forResource: "Launcher", withExtension: nil) {
        return url
    }
    // App bundle fallback — works in the distributed Appify.app
    let appBundleURL = Bundle.main.bundleURL
        .appendingPathComponent("Contents/Resources/Launcher")
    if FileManager.default.fileExists(atPath: appBundleURL.path) {
        return appBundleURL
    }
    return nil
}
