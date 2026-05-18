import Foundation
import Cocoa

struct IconConverter {

    /// Convert raw image data (any format NSImage can read) to .icns
    static func convertToIcns(pngData: Data, in tempDir: URL) -> URL? {
        guard let image = NSImage(data: pngData) else { return nil }
        let squared = squarePadded(image, size: 1024)
        guard let pngData = toPNG(squared) else { return nil }
        let pngPath = tempDir.appendingPathComponent("icon_sq.png")
        do { try pngData.write(to: pngPath) } catch { return nil }
        return buildIcns(from: pngPath, tempDir: tempDir)
    }

    /// Convert an existing image file to .icns
    static func convertPngToIcns(pngPath: URL, tempDir: URL) -> URL? {
        guard let image = NSImage(contentsOf: pngPath) else { return nil }
        let squared = squarePadded(image, size: 1024)
        guard let pngData = toPNG(squared) else { return nil }
        let squaredPath = tempDir.appendingPathComponent("icon_sq.png")
        do { try pngData.write(to: squaredPath) } catch { return nil }
        return buildIcns(from: squaredPath, tempDir: tempDir)
    }

    // MARK: - Square padding

    /// Fit the image into a square canvas with transparent background.
    /// The image is scaled proportionally to fill 85% of the canvas (standard macOS icon padding).
    private static func squarePadded(_ image: NSImage, size: Int) -> NSImage {
        let canvas = CGFloat(size)
        // Use the largest rep for best quality
        let srcSize: CGSize
        if let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }) {
            let w = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width
            let h = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height
            srcSize = CGSize(width: w, height: h)
        } else {
            srcSize = image.size
        }

        // Scale to fit inside 85% of canvas, preserving aspect ratio
        let maxContent = canvas * 0.85
        let scale = min(maxContent / srcSize.width, maxContent / srcSize.height)
        let drawW = srcSize.width * scale
        let drawH = srcSize.height * scale
        let drawX = (canvas - drawW) / 2
        let drawY = (canvas - drawH) / 2

        let result = NSImage(size: NSSize(width: canvas, height: canvas))
        result.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
        image.draw(
            in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
            from: NSRect(origin: .zero, size: srcSize),
            operation: .sourceOver,
            fraction: 1.0
        )
        result.unlockFocus()
        return result
    }

    // MARK: - PNG export

    private static func toPNG(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = image.size
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - .icns assembly

    private static func buildIcns(from pngPath: URL, tempDir: URL) -> URL? {
        let iconsetDir = tempDir.appendingPathComponent("icon.iconset")
        let icnsPath   = tempDir.appendingPathComponent("icon.icns")
        do { try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true) }
        catch { return nil }

        // Required iconset sizes (1x and 2x)
        let sizes = [16, 32, 128, 256, 512]
        for size in sizes {
            let out   = iconsetDir.appendingPathComponent("icon_\(size)x\(size).png")
            let out2x = iconsetDir.appendingPathComponent("icon_\(size)x\(size)@2x.png")
            guard sips(pngPath.path, size: size,    out: out.path)   else { return nil }
            guard sips(pngPath.path, size: size * 2, out: out2x.path) else { return nil }
        }

        guard run("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]) else { return nil }
        return icnsPath
    }

    // sips -z scales to exact pixel size (safe now because source is already square)
    private static func sips(_ src: String, size: Int, out: String) -> Bool {
        run("/usr/bin/sips", ["-z", "\(size)", "\(size)", src, "--out", out])
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        do { try proc.run(); proc.waitUntilExit(); return proc.terminationStatus == 0 }
        catch { return false }
    }
}
