import Foundation

struct FaviconFetcher {

    // Returns data only
    static func fetch(from urlString: String) -> Data? {
        fetchWithSource(from: urlString)?.0
    }

    // Returns (data, sourceURL) so callers can log where the image came from
    static func fetchWithSource(from urlString: String) -> (Data, String)? {
        guard let parsed = URL(string: urlString), let host = parsed.host else { return nil }
        let base = "\(parsed.scheme ?? "https")://\(host)"

        // Step 1: Parse HTML for high-res icons
        if let html = fetchText(urlString) {
            let candidates = extractIconURLs(from: html, base: base)
            for candidate in candidates {
                if let data = fetchImage(candidate), isUsableImage(data) {
                    return (data, candidate)
                }
            }
        }

        // Step 2: Well-known paths
        let wellKnown = [
            "\(base)/apple-touch-icon.png",
            "\(base)/apple-touch-icon-precomposed.png",
            "\(base)/favicon.png",
            "\(base)/icon.png",
            "\(base)/logo.png",
            "\(base)/favicon.ico",
        ]
        for url in wellKnown {
            if let data = fetchImage(url), isUsableImage(data) { return (data, url) }
        }

        // Step 3: Google favicon API — lower the size bar since it's always small
        let googleURL = "https://www.google.com/s2/favicons?domain=\(host)&sz=256"
        if let data = fetchImage(googleURL), data.count > 100 {
            return (data, googleURL)
        }

        return nil
    }

    // MARK: - HTML Parsing

    private static func extractIconURLs(from html: String, base: String) -> [String] {
        var results: [String] = []

        if let ogImage = extractMeta(html, property: "og:image") {
            results.append(resolve(ogImage, base: base))
        }
        if let twImage = extractMeta(html, property: "twitter:image") {
            results.append(resolve(twImage, base: base))
        }

        let touchIcons = extractLinkTags(html, rel: "apple-touch-icon")
        results.append(contentsOf: touchIcons.sorted { sizeOf($0) > sizeOf($1) }.map { resolve($0, base: base) })

        let icons = extractLinkTags(html, rel: "icon")
        let pngIcons = icons.filter { $0.lowercased().contains(".png") }
        results.append(contentsOf: pngIcons.sorted { sizeOf($0) > sizeOf($1) }.map { resolve($0, base: base) })

        if let manifestURL = extractManifestURL(html, base: base),
           let manifestText = fetchText(manifestURL),
           let iconURL = extractManifestIcon(manifestText, base: base) {
            results.append(iconURL)
        }

        // All remaining icon links including .ico
        let remaining = icons.filter { !$0.lowercased().contains(".png") }
        results.append(contentsOf: remaining.map { resolve($0, base: base) })

        return results
    }

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

    private static func extractLinkTags(_ html: String, rel: String) -> [String] {
        var results: [String] = []
        let p1 = "(?i)<link[^>]+rel=[\"'][^\"']*\(NSRegularExpression.escapedPattern(for: rel))[^\"']*[\"'][^>]+href=[\"']([^\"']+)[\"']"
        results.append(contentsOf: allMatches(p1, in: html, group: 1))
        let p2 = "(?i)<link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"'][^\"']*\(NSRegularExpression.escapedPattern(for: rel))[^\"']*[\"']"
        results.append(contentsOf: allMatches(p2, in: html, group: 1))
        return results
    }

    private static func extractManifestURL(_ html: String, base: String) -> String? {
        let p1 = "(?i)<link[^>]+rel=[\"']manifest[\"'][^>]+href=[\"']([^\"']+)[\"']"
        if let href = firstMatch(p1, in: html, group: 1) { return resolve(href, base: base) }
        let p2 = "(?i)<link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"']manifest[\"']"
        if let href = firstMatch(p2, in: html, group: 1) { return resolve(href, base: base) }
        return nil
    }

    private static func extractManifestIcon(_ json: String, base: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = obj["icons"] as? [[String: Any]] else { return nil }
        let sorted = icons.sorted {
            sizeFromManifest($0["sizes"] as? String ?? "") > sizeFromManifest($1["sizes"] as? String ?? "")
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
        if let match = firstMatch("(\\d+)x\\d+", in: url, group: 1), let n = Int(match) { return n }
        return 0
    }

    private static func sizeFromManifest(_ sizes: String) -> Int {
        Int(sizes.lowercased().components(separatedBy: "x").first ?? "") ?? 0
    }

    private static func isUsableImage(_ data: Data) -> Bool {
        guard data.count > 500 else { return false }
        if let str = String(data: data.prefix(50), encoding: .utf8),
           str.lowercased().contains("<html") || str.lowercased().hasPrefix("<!") { return false }
        return true
    }

    // MARK: - Network

    static func fetchImage(_ urlString: String) -> Data? { fetchRaw(urlString, timeout: 8) }
    static func fetchText(_ urlString: String) -> String? {
        guard let data = fetchRaw(urlString, timeout: 10) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func fetchRaw(_ urlString: String, timeout: TimeInterval) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,image/*,*/*", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
            sem.signal()
        }.resume()
        sem.wait()
        return result
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
