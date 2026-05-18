import Foundation

struct FaviconFetcher {

    // Main entry: returns the best icon data found for a given URL
    static func fetch(from urlString: String) -> Data? {
        guard let parsed = URL(string: urlString), let host = parsed.host else { return nil }
        let base = "\(parsed.scheme ?? "https")://\(host)"

        // Step 1: Fetch the page HTML and extract icon URLs from meta tags
        if let html = fetchText(urlString) {
            let candidates = extractIconURLs(from: html, base: base)
            for candidate in candidates {
                if let data = fetchImage(candidate), isUsableImage(data) {
                    return data
                }
            }
        }

        // Step 2: Well-known paths (no HTML parsing needed)
        let wellKnown = [
            "\(base)/apple-touch-icon.png",
            "\(base)/apple-touch-icon-precomposed.png",
            "\(base)/favicon.png",
            "\(base)/icon.png",
            "\(base)/logo.png",
        ]
        for url in wellKnown {
            if let data = fetchImage(url), isUsableImage(data) { return data }
        }

        // Step 3: Google favicon API as last resort (always returns something)
        if let data = fetchImage("https://www.google.com/s2/favicons?domain=\(host)&sz=256"),
           isUsableImage(data) { return data }

        return nil
    }

    // MARK: - HTML Parsing

    // Returns icon URLs in priority order: high-res first, favicon last
    private static func extractIconURLs(from html: String, base: String) -> [String] {
        var results: [String] = []

        // 1. og:image — usually the highest quality brand image
        if let ogImage = extractMeta(html, property: "og:image") {
            results.append(resolve(ogImage, base: base))
        }

        // 2. twitter:image
        if let twImage = extractMeta(html, property: "twitter:image") {
            results.append(resolve(twImage, base: base))
        }

        // 3. apple-touch-icon (all sizes, largest first)
        let touchIcons = extractLinkTags(html, rel: "apple-touch-icon")
        let sortedTouch = touchIcons.sorted { sizeOf($0) > sizeOf($1) }
        results.append(contentsOf: sortedTouch.map { resolve($0, base: base) })

        // 4. icon links (PNG preferred, largest first)
        let icons = extractLinkTags(html, rel: "icon")
        let pngIcons = icons.filter { $0.lowercased().contains(".png") }
        let sortedPng = pngIcons.sorted { sizeOf($0) > sizeOf($1) }
        results.append(contentsOf: sortedPng.map { resolve($0, base: base) })

        // 5. Web app manifest — fetch and parse for icons array
        if let manifestURL = extractManifestURL(html, base: base),
           let manifestText = fetchText(manifestURL),
           let iconURL = extractManifestIcon(manifestText, base: base) {
            results.append(iconURL)
        }

        // 6. Any remaining icon links
        let remaining = icons.filter { !$0.lowercased().contains(".png") }
        results.append(contentsOf: remaining.map { resolve($0, base: base) })

        return results
    }

    // Extract <meta property="X" content="Y"> or <meta name="X" content="Y">
    private static func extractMeta(_ html: String, property: String) -> String? {
        let patterns = [
            "(?i)<meta[^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "(?i)<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: property))[\"']",
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern, in: html, group: 1) { return match }
        }
        return nil
    }

    // Extract href values from <link rel="X" ...> tags
    private static func extractLinkTags(_ html: String, rel: String) -> [String] {
        var results: [String] = []
        // Match both rel="apple-touch-icon" and rel="apple-touch-icon shortcut" etc.
        let pattern = "(?i)<link[^>]+rel=[\"'][^\"']*\(NSRegularExpression.escapedPattern(for: rel))[^\"']*[\"'][^>]+href=[\"']([^\"']+)[\"']"
        let matches = allMatches(pattern, in: html, group: 1)
        results.append(contentsOf: matches)
        // Also try href before rel
        let pattern2 = "(?i)<link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"'][^\"']*\(NSRegularExpression.escapedPattern(for: rel))[^\"']*[\"']"
        results.append(contentsOf: allMatches(pattern2, in: html, group: 1))
        return results
    }

    private static func extractManifestURL(_ html: String, base: String) -> String? {
        let pattern = "(?i)<link[^>]+rel=[\"']manifest[\"'][^>]+href=[\"']([^\"']+)[\"']"
        if let href = firstMatch(pattern, in: html, group: 1) { return resolve(href, base: base) }
        let pattern2 = "(?i)<link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"']manifest[\"']"
        if let href = firstMatch(pattern2, in: html, group: 1) { return resolve(href, base: base) }
        return nil
    }

    // Parse manifest JSON for the largest icon
    private static func extractManifestIcon(_ json: String, base: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = obj["icons"] as? [[String: Any]] else { return nil }
        // Pick largest by sizes field (e.g. "512x512")
        let sorted = icons.sorted {
            let a = sizeFromManifest($0["sizes"] as? String ?? "")
            let b = sizeFromManifest($1["sizes"] as? String ?? "")
            return a > b
        }
        if let src = sorted.first?["src"] as? String { return resolve(src, base: base) }
        return nil
    }

    // MARK: - Helpers

    private static func resolve(_ href: String, base: String) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return href }
        if href.hasPrefix("//") { return "https:" + href }
        if href.hasPrefix("/") { return base + href }
        return base + "/" + href
    }

    private static func sizeOf(_ url: String) -> Int {
        // Extract size hint from URL or filename e.g. "icon-192x192.png" -> 192
        let pattern = "(\\d+)x\\d+"
        if let match = firstMatch(pattern, in: url, group: 1), let n = Int(match) { return n }
        return 0
    }

    private static func sizeFromManifest(_ sizes: String) -> Int {
        let parts = sizes.lowercased().components(separatedBy: "x")
        return Int(parts.first ?? "") ?? 0
    }

    private static func isUsableImage(_ data: Data) -> Bool {
        // Must be at least 1KB and not an HTML error page
        guard data.count > 1000 else { return false }
        // Reject HTML responses disguised as images
        if let str = String(data: data.prefix(50), encoding: .utf8),
           str.lowercased().hasPrefix("<!") { return false }
        return true
    }

    // MARK: - Network

    static func fetchImage(_ urlString: String) -> Data? {
        return fetchRaw(urlString, timeout: 8)
    }

    static func fetchText(_ urlString: String) -> String? {
        guard let data = fetchRaw(urlString, timeout: 10) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func fetchRaw(_ urlString: String, timeout: TimeInterval) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,*/*", forHTTPHeaderField: "Accept")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data? = nil
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data = data,
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return result
    }

    // MARK: - Regex helpers

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
        return regex.matches(in: text, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }
}
