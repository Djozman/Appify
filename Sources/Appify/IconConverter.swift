import Foundation
import Cocoa

struct IconConverter {

    /// Convert raw image data (any format) to .icns
    static func convertToIcns(pngData: Data, in tempDir: URL) -> URL? {
        let ext = imageExtension(for: pngData)

        // SVG: rasterize via NSImage directly (sips cannot handle SVG)
        if ext == "svg" {
            guard let image = NSImage(data: pngData) else { return nil }
            // Force rasterize at high res
            let rasterized = rasterize(image, size: 1024)
            let squared = squarePadded(rasterized, size: 1024)
            guard let squaredData = toPNG(squared) else { return nil }
            let squaredPath = tempDir.appendingPathComponent("icon_sq.png")
            do { try squaredData.write(to: squaredPath) } catch { return nil }
            return buildIcns(from: squaredPath, tempDir: tempDir)
        }

        // ICO: extract best frame via NSImage (handles multi-resolution ICO)
        if ext == "ico" {
            let srcPath = tempDir.appendingPathComponent("icon_src.ico")
            do { try pngData.write(to: srcPath) } catch { return nil }
            // Try NSImage first (works for most ICOs)
            if let image = NSImage(contentsOf: srcPath) {
                let squared = squarePadded(image, size: 1024)
                guard let squaredData = toPNG(squared) else { return nil }
                let squaredPath = tempDir.appendingPathComponent("icon_sq.png")
                do { try squaredData.write(to: squaredPath) } catch { return nil }
                return buildIcns(from: squaredPath, tempDir: tempDir)
            }
            // Fallback: sips format conversion
            let converted = tempDir.appendingPathComponent("icon_converted.png")
            if run("/usr/bin/sips", ["-s", "format", "png", srcPath.path, "--out", converted.path]),
               let image = NSImage(contentsOf: converted) {
                let squared = squarePadded(image, size: 1024)
                guard let squaredData = toPNG(squared) else { return nil }
                let squaredPath = tempDir.appendingPathComponent("icon_sq.png")
                do { try squaredData.write(to: squaredPath) } catch { return nil }
                return buildIcns(from: squaredPath, tempDir: tempDir)
            }
            return nil
        }

        // JPEG / PNG / WebP / GIF / TIFF / BMP
        let srcPath = tempDir.appendingPathComponent("icon_src.\(ext)")
        do { try pngData.write(to: srcPath) } catch { return nil }

        // Convert non-PNG to PNG via sips if needed
        let pngPath: URL
        if ext == "png" {
            pngPath = srcPath
        } else {
            let converted = tempDir.appendingPathComponent("icon_converted.png")
            if run("/usr/bin/sips", ["-s", "format", "png", srcPath.path, "--out", converted.path]) {
                pngPath = converted
            } else if let image = NSImage(data: pngData), let data = toPNG(image) {
                let fallback = tempDir.appendingPathComponent("icon_fallback.png")
                do { try data.write(to: fallback) } catch { return nil }
                pngPath = fallback
            } else {
                return nil
            }
        }

        guard let image = NSImage(contentsOf: pngPath) else { return nil }

        // Detect aspect ratio — if wide (og:image banner), center-square crop instead of letterbox
        let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide })
        let pw = rep.flatMap { $0.pixelsWide > 0 ? $0.pixelsWide : nil } ?? Int(image.size.width)
        let ph = rep.flatMap { $0.pixelsHigh > 0 ? $0.pixelsHigh : nil } ?? Int(image.size.height)
        let ratio = Double(pw) / Double(max(ph, 1))

        let finalImage: NSImage
        if ratio > 1.3 {
            // Wide image (banner/og:image) — center-square crop
            finalImage = centerCrop(image, pixelW: pw, pixelH: ph)
        } else {
            // Already squarish — just pad
            finalImage = squarePadded(image, size: 1024)
        }

        guard let squaredData = toPNG(finalImage) else { return nil }
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

    static func imageExtension(for data: Data) -> String {
        guard data.count >= 4 else { return "png" }
        let b = [UInt8](data.prefix(16))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.starts(with: [0xFF, 0xD8])               { return "jpg" }
        if b.starts(with: [0x47, 0x49, 0x46])         { return "gif" }
        if b.starts(with: [0x49, 0x49]) || b.starts(with: [0x4D, 0x4D]) { return "tiff" }
        if b.starts(with: [0x42, 0x4D])               { return "bmp" }
        if b.starts(with: [0x00, 0x00, 0x01, 0x00])   { return "ico" }
        if b.count >= 12, b[0...3] == [0x52,0x49,0x46,0x46][...],
           [UInt8](data[8..<12]) == [0x57,0x45,0x42,0x50] { return "webp" }
        if b.starts(with: [0x69, 0x63, 0x6E, 0x73])   { return "icns" }
        // SVG detection: look for "<svg" in first 512 bytes
        if let text = String(data: data.prefix(512), encoding: .utf8),
           text.lowercased().contains("<svg") { return "svg" }
        return "png"
    }

    // MARK: - Image transforms

    /// Force NSImage to rasterize at a specific pixel size (important for SVG)
    private static func rasterize(_ image: NSImage, size: Int) -> NSImage {
        let s = CGFloat(size)
        let result = NSImage(size: NSSize(width: s, height: s))
        result.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: s, height: s),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// Fit image into a square canvas with 85% fill and transparent background
    private static func squarePadded(_ image: NSImage, size: Int) -> NSImage {
        let canvas = CGFloat(size)
        let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide })
        let w = rep.flatMap { $0.pixelsWide > 0 ? CGFloat($0.pixelsWide) : nil } ?? image.size.width
        let h = rep.flatMap { $0.pixelsHigh > 0 ? CGFloat($0.pixelsHigh) : nil } ?? image.size.height
        let srcSize = CGSize(width: max(w, 1), height: max(h, 1))
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
        image.draw(in: NSRect(x: drawX, y: drawY, width: drawW, height: drawH),
                   from: NSRect(origin: .zero, size: srcSize),
                   operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }

    /// Center-square crop: takes the middle square of a wide image
    private static func centerCrop(_ image: NSImage, pixelW: Int, pixelH: Int) -> NSImage {
        let side = CGFloat(min(pixelW, pixelH))
        let srcX = (CGFloat(pixelW) - side) / 2
        let srcY = (CGFloat(pixelH) - side) / 2
        let canvas: CGFloat = 1024
        let result = NSImage(size: NSSize(width: canvas, height: canvas))
        result.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas),
                   from: NSRect(x: srcX, y: srcY, width: side, height: side),
                   operation: .sourceOver, fraction: 1.0)
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
        for size in [16, 32, 128, 256, 512] {
            let out   = iconsetDir.appendingPathComponent("icon_\(size)x\(size).png")
            let out2x = iconsetDir.appendingPathComponent("icon_\(size)x\(size)@2x.png")
            guard sips(pngPath.path, size: size,     out: out.path)   else { return nil }
            guard sips(pngPath.path, size: size * 2, out: out2x.path) else { return nil }
        }
        guard run("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsPath.path]) else { return nil }
        return icnsPath
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
