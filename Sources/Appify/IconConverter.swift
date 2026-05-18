import Foundation
import Cocoa

struct IconConverter {

    /// Convert raw image data (any format) to .icns
    static func convertToIcns(pngData: Data, in tempDir: URL) -> URL? {
        // Write raw bytes first so sips can identify the format
        let rawPath = tempDir.appendingPathComponent("icon_raw")
        do { try pngData.write(to: rawPath) } catch { return nil }

        // Detect format from magic bytes
        let ext = imageExtension(for: pngData)
        let srcPath = tempDir.appendingPathComponent("icon_src.\(ext)")
        do { try pngData.write(to: srcPath) } catch { return nil }

        // If it's not already a PNG, use sips to convert to PNG first
        let pngPath: URL
        if ext == "png" {
            pngPath = srcPath
        } else {
            let converted = tempDir.appendingPathComponent("icon_converted.png")
            // sips can handle ico, gif, tiff, bmp, webp on macOS
            if run("/usr/bin/sips", ["-s", "format", "png", srcPath.path, "--out", converted.path]) {
                pngPath = converted
            } else {
                // Last resort: try NSImage decode anyway
                guard let image = NSImage(data: pngData) else { return nil }
                guard let reencoded = toPNG(image) else { return nil }
                let fallback = tempDir.appendingPathComponent("icon_fallback.png")
                do { try reencoded.write(to: fallback) } catch { return nil }
                pngPath = fallback
            }
        }

        // Now load as NSImage for square-padding
        guard let image = NSImage(contentsOf: pngPath) else {
            // If NSImage still can't read it, try sips pixel dimensions directly
            return buildIcnsDirectly(from: pngPath, tempDir: tempDir)
        }

        let squared = squarePadded(image, size: 1024)
        guard let squaredData = toPNG(squared) else { return nil }
        let squaredPath = tempDir.appendingPathComponent("icon_sq.png")
        do { try squaredData.write(to: squaredPath) } catch { return nil }
        return buildIcns(from: squaredPath, tempDir: tempDir)
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

    // MARK: - Format detection

    private static func imageExtension(for data: Data) -> String {
        guard data.count >= 4 else { return "png" }
        let bytes = [UInt8](data.prefix(16))
        // PNG: 89 50 4E 47
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        // JPEG: FF D8
        if bytes.starts(with: [0xFF, 0xD8]) { return "jpg" }
        // GIF: 47 49 46
        if bytes.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        // TIFF: 49 49 or 4D 4D
        if bytes.starts(with: [0x49, 0x49]) || bytes.starts(with: [0x4D, 0x4D]) { return "tiff" }
        // BMP: 42 4D
        if bytes.starts(with: [0x42, 0x4D]) { return "bmp" }
        // ICO: 00 00 01 00
        if bytes.starts(with: [0x00, 0x00, 0x01, 0x00]) { return "ico" }
        // WebP: 52 49 46 46 ... 57 45 42 50
        if bytes.count >= 12, bytes[0...3] == [0x52,0x49,0x46,0x46][...],
           [UInt8](data[8..<12]) == [0x57,0x45,0x42,0x50] { return "webp" }
        // ICNS: 69 63 6E 73
        if bytes.starts(with: [0x69, 0x63, 0x6E, 0x73]) { return "icns" }
        return "png" // assume PNG as fallback
    }

    // MARK: - Square padding

    private static func squarePadded(_ image: NSImage, size: Int) -> NSImage {
        let canvas = CGFloat(size)
        let srcSize: CGSize
        if let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }) {
            let w = rep.pixelsWide > 0 ? CGFloat(rep.pixelsWide) : image.size.width
            let h = rep.pixelsHigh > 0 ? CGFloat(rep.pixelsHigh) : image.size.height
            srcSize = CGSize(width: max(w, 1), height: max(h, 1))
        } else {
            srcSize = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        }
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
        let sizes = [16, 32, 128, 256, 512]
        for size in sizes {
            let out   = iconsetDir.appendingPathComponent("icon_\(size)x\(size).png")
            let out2x = iconsetDir.appendingPathComponent("icon_\(size)x\(size)@2x.png")
            guard sips(pngPath.path, size: size,     out: out.path)   else { return nil }
            guard sips(pngPath.path, size: size * 2, out: out2x.path) else { return nil }
        }
        guard run("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]) else { return nil }
        return icnsPath
    }

    /// Fallback: skip NSImage entirely, let sips do all the work
    private static func buildIcnsDirectly(from pngPath: URL, tempDir: URL) -> URL? {
        // Resize to square using sips padding trick: expand canvas then resize
        let squaredPath = tempDir.appendingPathComponent("icon_sq_direct.png")
        // Get image dimensions
        var w = 0, h = 0
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        proc.arguments = ["--getProperty", "pixelWidth", "--getProperty", "pixelHeight", pngPath.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run(); proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in out.components(separatedBy: "\n") {
            if line.contains("pixelWidth"), let v = line.components(separatedBy: ":").last.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) { w = v }
            if line.contains("pixelHeight"), let v = line.components(separatedBy: ":").last.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) { h = v }
        }
        let side = max(w, h, 1)
        // Pad to square with sips --padColor
        if run("/usr/bin/sips", ["-z", "\(side)", "\(side)", "--padColor", "00000000", pngPath.path, "--out", squaredPath.path]) {
            return buildIcns(from: squaredPath, tempDir: tempDir)
        }
        return buildIcns(from: pngPath, tempDir: tempDir)
    }

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
