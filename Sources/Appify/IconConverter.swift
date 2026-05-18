import Foundation

struct IconConverter {
    static func convertToIcns(pngData: Data, in tempDir: URL) -> URL? {
        let pngPath = tempDir.appendingPathComponent("icon_src.png")
        do {
            try pngData.write(to: pngPath)
        } catch {
            return nil
        }
        return convertPngToIcns(pngPath: pngPath, tempDir: tempDir)
    }

    static func convertPngToIcns(pngPath: URL, tempDir: URL) -> URL? {
        let iconsetDir = tempDir.appendingPathComponent("icon.iconset")
        let icnsPath = tempDir.appendingPathComponent("icon.icns")

        do {
            try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
        } catch { return nil }

        let sizes = [16, 32, 64, 128, 256, 512]
        for size in sizes {
            let out = iconsetDir.appendingPathComponent("icon_\(size)x\(size).png")
            let out2x = iconsetDir.appendingPathComponent("icon_\(size)x\(size)@2x.png")
            guard run("/usr/bin/sips", ["-z", "\(size)", "\(size)", pngPath.path, "--out", out.path]) else { return nil }
            guard run("/usr/bin/sips", ["-z", "\(size * 2)", "\(size * 2)", pngPath.path, "--out", out2x.path]) else { return nil }
        }

        guard run("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]) else { return nil }
        return icnsPath
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch { return false }
    }
}
