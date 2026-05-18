import Foundation

public struct FaviconFetcher {

    public static func fetch(from urlString: String) -> Data? {
        fetchWithSource(from: urlString)?.0
    }

    public static func fetchWithSource(from urlString: String) -> (Data, String)? {
        guard let parsed = URL(string: urlString), let host = parsed.host else { return nil }
        let base = "\(parsed.scheme ?? "https")://\(host)"

        if let html = fetchText(urlString) {
            let candidates = extractIconURLs(from: html, base: base)
            for candidate in candidates {
                if let data = fetchImage(candidate), isUsableImage(data) {
                    return (data, candidate)
                }
            }
        }

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

        let googleURL = "https://www.google.com/s2/favicons?domain=\(host)&sz=256"
        if let data = fetchImage(googleURL), data.count > 100 { return (data, googleURL) }

        return nil
    }

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
        if let manifestURL = extractManifestURL(html, base: base),
           let manifestText = fetchText(manifestURL),
           let iconURL = extractManifestIcon(manifestText, base: base) {
            results.append(iconURL)
        }
        if let ogImage = extractMeta(html, property: "og:image") { results.append(resolve(ogImage, base: base)) }
        if let twImage = extractMeta(html, property: "twitter:image") { results.append(resolve(twImage, base: base)) }
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

    private static func extractManifestURL(_ html: String, base: String) -> String? {
        let p1 = "(?i)<link[^>]+rel=[\"']manifest[\"'][^>]+href=[\"']([^\"']+)[\"']"
        if let h = firstMatch(p1, in: html, group: 1) { return resolve(h, base: base) }
        let p2 = "(?i)<link[^>]+href=[\"']([^\"']+)[\"'][^>]+rel=[\"']manifest[\"']"
        if let h = firstMatch(p2, in: html, group: 1) { return resolve(h, base: base) }
        return nil
    }

    private static func extractManifestIcon(_ json: String, base: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = obj["icons"] as? [[String: Any]] else { return nil }
        let sorted = icons.sorted { sizeFromManifest($0["sizes"] as? String ?? "") > sizeFromManifest($1["sizes"] as? String ?? "") }
        if let src = sorted.first?["src"] as? String { return resolve(src, base: base) }
        return nil
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

    private static func sizeFromManifest(_ sizes: String) -> Int {
        Int(sizes.lowercased().components(separatedBy: "x").first ?? "") ?? 0
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

    public static func fetchImage(_ urlString: String) -> Data? { fetchRaw(urlString, timeout: 8) }
    public static func fetchText(_ urlString: String) -> String? {
        guard let data = fetchRaw(urlString, timeout: 10) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func fetchRaw(_ urlString: String, timeout: TimeInterval) -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,image/svg+xml,image/*,*/*", forHTTPHeaderField: "Accept")
        let sem = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
            sem.signal()
        }.resume()
        sem.wait()
        return result
    }

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
