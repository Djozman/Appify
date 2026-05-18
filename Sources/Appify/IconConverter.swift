import Foundation
import Cocoa

struct IconConverter {

    // MARK: - Public API

    /// Produce the same processed NSImage that `convertToIcns` would embed —
    /// so the SetupUI preview is pixel-identical to the final .app icon.
    static func previewImage(for faviconData: Data, size: CGFloat = 80) -> NSImage? {
        guard let processed = processedImage(for: faviconData) else { return nil }
        let preview = NSImage(size: NSSize(width: size, height: size))
        preview.lockFocus()
        processed.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
                       from: .zero, operation: .copy, fraction: 1.0)
        preview.unlockFocus()
        return preview
    }

    static func convertToIcns(pngData: Data, in tempDir: URL) -> URL? {
        guard let processed = processedImage(for: pngData) else { return nil }
        guard let squaredData = toPNG(processed) else { return nil }
        let squaredPath = tempDir.appendingPathComponent("icon_sq.png")
        do { try squaredData.write(to: squaredPath) } catch { return nil }
        return buildIcns(from: squaredPath, tempDir: tempDir)
    }

    // MARK: - Core image processing (shared by preview & icns)

    /// Apply the same compositing (background, padding, rounding, cropping)
    /// that `convertToIcns` uses, returning a 1024x1024 NSImage ready for
    /// either preview downscaling or PNG to .icns conversion.
    private static func processedImage(for data: Data) -> NSImage? {
        let ext = imageExtension(for: data)
        let size = 1024

        switch ext {
        case "svg":
            guard let image = NSImage(data: data) else { return nil }
            return rasterizeSVG(image, svgData: data, size: size)

        case "ico":
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("appify_preview_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let srcPath = tmp.appendingPathComponent("icon.ico")
            do { try data.write(to: srcPath) } catch { return nil }

            // Try NSImage first, then sips fallback
            if let image = NSImage(contentsOf: srcPath) {
                return squarePadded(image, size: size)
            }
            let converted = tmp.appendingPathComponent("icon.png")
            if run("/usr/bin/sips", ["-s", "format", "png", srcPath.path, "--out", converted.path]),
               let image = NSImage(contentsOf: converted) {
                return squarePadded(image, size: size)
            }
            return nil

        default:
            // PNG, JPG, GIF, TIFF, BMP, WebP — NSImage can open these directly
            guard let image = NSImage(data: data) else { return nil }
            let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide })
            let pw = rep.flatMap { $0.pixelsWide > 0 ? $0.pixelsWide : nil } ?? Int(image.size.width)
            let ph = rep.flatMap { $0.pixelsHigh > 0 ? $0.pixelsHigh : nil } ?? Int(image.size.height)
            let ratio = Double(pw) / Double(max(ph, 1))
            if ratio > 1.3 {
                return centerCrop(image, pixelW: pw, pixelH: ph)
            } else {
                return squarePadded(image, size: size)
            }
        }
    }

    /// Return the fully composited 1024x1024 PNG data — same as what
    /// `convertToIcns` feeds into iconutil.
    static func processedPNG(for faviconData: Data) -> Data? {
        guard let processed = processedImage(for: faviconData) else { return nil }
        return toPNG(processed)
    }

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
        if let text = String(data: data.prefix(512), encoding: .utf8),
           text.lowercased().contains("<svg") { return "svg" }
        return "png"
    }

    // MARK: - SVG rasterization

    /// Rasterize SVG, auto-detecting if it needs a colored background
    /// (e.g. white-on-transparent icons like monochrome.tf)
    private static func rasterizeSVG(_ image: NSImage, svgData: Data, size: Int) -> NSImage {
        let s = CGFloat(size)
        let needsBackground = svgIsLightOnTransparent(svgData)
        let bgColor: NSColor = needsBackground ? darkBackgroundForSVG(svgData) : .clear
        let padding: CGFloat = needsBackground ? 0.12 : 0.075  // tighter crop when using bg

        let canvas = NSImage(size: NSSize(width: s, height: s))
        canvas.lockFocus()

        if needsBackground {
            // Rounded rect background (macOS app icon style)
            bgColor.setFill()
            let radius = s * 0.22
            let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
                                      xRadius: radius, yRadius: radius)
            bgPath.fill()
        } else {
            NSColor.clear.setFill()
            NSRect(x: 0, y: 0, width: s, height: s).fill()
        }

        let inset = s * padding
        let drawSize = s - inset * 2
        image.draw(in: NSRect(x: inset, y: inset, width: drawSize, height: drawSize),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
        canvas.unlockFocus()
        return canvas
    }

    /// Returns true if the SVG uses white/light fill with no background
    private static func svgIsLightOnTransparent(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let lower = text.lowercased()
        // No rect/background fill covering the canvas
        let hasBackground = lower.contains("background") || lower.contains("rect")
        // Has white or near-white fill
        let hasWhiteFill = lower.contains("fill=\"white\"") ||
                           lower.contains("fill='white'") ||
                           lower.contains("fill=\"#fff\"") ||
                           lower.contains("fill=\"#ffffff\"") ||
                           lower.contains("fill: white") ||
                           lower.contains("fill: #fff")
        return hasWhiteFill && !hasBackground
    }

    /// Pick a background color — use the site's brand feel (dark/neutral)
    private static func darkBackgroundForSVG(_ data: Data) -> NSColor {
        // Default: dark charcoal, works well for most light-icon SVGs
        return NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
    }

    // MARK: - Image transforms

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
