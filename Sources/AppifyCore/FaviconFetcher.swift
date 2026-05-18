import Foundation

public struct FaviconFetcher {

    private static let requestTimeout: TimeInterval = 5

    /// Sync — called from DispatchQueue.global(), no Swift concurrency involved.
    public static func fetch(from urlString: String) -> Data? {
        fetchWithSource(from: urlString)?.0
    }

    /// Sync — tries sources in order, returns first usable image within timeout.
    public static func fetchWithSource(from urlString: String) -> (Data, String)? {
        guard let parsed = URL(string: urlString), let host = parsed.host else { return nil }
        let base = "\(parsed.scheme ?? "https")://\(host)"

        // 1. Google favicon service
        let googleURL = "https://www.google.com/s2/favicons?domain=\(host)&sz=256"
        if let data = fetchSync(googleURL), data.count > 100 {
            return (data, googleURL)
        }

        // 2. apple-touch-icon
        let touchIcon = "\(base)/apple-touch-icon.png"
        if let data = fetchSync(touchIcon), isUsableImage(data) {
            return (data, touchIcon)
        }

        // 3. favicon.ico
        let faviconIco = "\(base)/favicon.ico"
        if let data = fetchSync(faviconIco), isUsableImage(data) {
            return (data, faviconIco)
        }

        // 4. Parse HTML for icon links
        if let html = fetchTextSync(urlString) {
            for candidate in extractIconURLs(from: html, base: base).prefix(3) {
                if let data = fetchSync(candidate), isUsableImage(data) {
                    return (data, candidate)
                }
            }
        }

        return nil
    }

    // MARK: - Sync network

    private static func fetchSync(_ urlString: String) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")

        var result: Data? = nil
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + requestTimeout + 1)
        return result
    }

    private static func fetchTextSync(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,*/*", forHTTPHeaderField: "Accept")

        var result: String? = nil
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + requestTimeout + 1)
        return result
    }

    // MARK: - Async API (kept for any callers that use it)

    public static func fetchWithSourceAsync(from urlString: String) async -> (Data, String)? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: fetchWithSource(from: urlString))
            }
        }
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
        if let og = extractMeta(html, property: "og:image") { results.append(resolve(og, base: base)) }
        if let tw = extractMeta(html, property: "twitter:image") { results.append(resolve(tw, base: base)) }
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
