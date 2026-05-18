import Foundation

public struct FaviconFetcher {

    private static let requestTimeout: TimeInterval = 4

    /// Sync wrapper — returns within 10 seconds max.
    public static func fetch(from urlString: String) -> Data? {
        fetchWithSource(from: urlString)?.0
    }

    /// Sync wrapper — returns within 10 seconds max.
    /// Uses Task.detached so it never inherits a blocked actor executor (e.g. runModal).
    public static func fetchWithSource(from urlString: String) -> (Data, String)? {
        final class Box: @unchecked Sendable { var value: (Data, String)? }
        let sem = DispatchSemaphore(value: 0)
        let box = Box()
        Task.detached {
            box.value = await fetchWithSourceAsync(from: urlString)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
        return box.value
    }

    public static func fetchWithSourceAsync(from urlString: String) async -> (Data, String)? {
        guard let parsed = URL(string: urlString), let host = parsed.host else { return nil }
        let base = "\(parsed.scheme ?? "https")://\(host)"

        // 1. Google favicon service — fast, reliable, works for most domains
        let googleURL = "https://www.google.com/s2/favicons?domain=\(host)&sz=256"
        if let data = await fetchImage(googleURL), data.count > 100 {
            return (data, googleURL)
        }

        // 2. apple-touch-icon
        let appleTouchIcon = "\(base)/apple-touch-icon.png"
        if let data = await fetchImage(appleTouchIcon), isUsableImage(data) {
            return (data, appleTouchIcon)
        }

        // 3. favicon.ico
        let faviconIco = "\(base)/favicon.ico"
        if let data = await fetchImage(faviconIco), isUsableImage(data) {
            return (data, faviconIco)
        }

        // 4. Parse HTML
        if let html = await fetchText(urlString) {
            let candidates = extractIconURLs(from: html, base: base)
            for candidate in candidates.prefix(3) {
                if let data = await fetchImage(candidate), isUsableImage(data) {
                    return (data, candidate)
                }
            }
        }

        return nil
    }

    // MARK: - HTML Parsing

    private static func extractIconURLs(from html: String, base: String) -> [String] {
        var results: [String] = []

        let touchIcons = extractLinkTags(html, rel: "apple-touch-icon")
        results.append(contentsOf: touchIcons.sorted { sizeOf($0) > sizeOf($1) }.map { resolve($0, base: base) })

        let icons = extractLinkTags(html, rel: "icon")
        let svgIcons = icons.filter { $0.lowercased().contains(".svg") }
        let pngIcons = icons.filter { $0.lowercased().contains(".png") }
        let otherIcons = icons.filter { !$0.lowercased().contains(".svg") && !$0.lowercased().contains(".png") }
        results.append(contentsOf: svgIcons.map { resolve($0, base: base) })
        results.append(contentsOf: pngIcons.sorted { sizeOf($0) > sizeOf($1) }.map { resolve($0, base: base) })
        results.append(contentsOf: otherIcons.map { resolve($0, base: base) })

        if let ogImage = extractMeta(html, property: "og:image") {
            results.append(resolve(ogImage, base: base))
        }
        if let twImage = extractMeta(html, property: "twitter:image") {
            results.append(resolve(twImage, base: base))
        }

        return results
    }

    private static func extractMeta(_ html: String, property: String) -> String? {
        let patterns = [
            "(?i)<meta[^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "(?i)<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"']",
        ]
        for p in patterns { if let m = firstMatch(p, in: html, group: 1) { return m } }
        return nil
    }

    private static func extractLinkTags(_ html: String, rel: String) -> [String] {
        var results: [String] = []
        let p1 = "(?i)<link[^>]+rel=[\"'][^\"']*\(NSRegularExpression.escapedPattern(for: rel))[^\"']*[\"'][^>]+href=[\"']([^\"']+)[\"']"
        results.append(contentsOf: allMatches(p1, in: html, group: 1))
        let p2 = "(?i)<link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"'][^\"']*\(NSRegularExpression.escapedPattern(for: rel))[^\"']*[\"']"
        results.append(contentsOf: allMatches(p2, in: html, group: 1))
        return results
    }

    // MARK: - Helpers

    private static func resolve(_ href: String, base: String) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
        if href.hasPrefix("//") { return "https:" + href }
        if href.hasPrefix("/") { return base + href }
        return base + "/" + href
    }

    private static func sizeOf(_ url: String) -> Int {
        if let m = firstMatch("(\\d+)x\\d+", in: url, group: 1), let n = Int(m) { return n }
        return 0
    }

    private static func isUsableImage(_ data: Data) -> Bool {
        if let text = String(data: data.prefix(512), encoding: .utf8),
           text.contains("<svg") || text.contains("<?xml") {
            return !text.lowercased().contains("<html")
        }
        guard data.count > 200 else { return false }
        if let str = String(data: data.prefix(50), encoding: .utf8),
           str.lowercased().contains("<html") || str.lowercased().hasPrefix("<!") { return false }
        return true
    }

    // MARK: - Network (async)

    public static func fetchImage(_ urlString: String) async -> Data? { await fetchRaw(urlString) }
    public static func fetchText(_ urlString: String) async -> String? {
        guard let data = await fetchRaw(urlString) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func fetchRaw(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,image/svg+xml,image/*,*/*", forHTTPHeaderField: "Accept")

        return await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        return data
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(requestTimeout + 2) * 1_000_000_000)
                return nil
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Regex

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let r = Range(match.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    private static func allMatches(_ pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            guard $0.numberOfRanges > group, let r = Range($0.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }
}
