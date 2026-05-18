import Foundation

struct FaviconFetcher {
    static func fetch(from urlString: String) -> Data? {
        guard let parsed = URL(string: urlString), let host = parsed.host else { return nil }
        let base = "\(parsed.scheme ?? "https")://\(host)"
        let candidates = [
            "\(base)/apple-touch-icon.png",
            "\(base)/apple-touch-icon-precomposed.png",
            "\(base)/favicon.png",
            "\(base)/favicon.ico",
            "https://www.google.com/s2/favicons?domain=\(host)&sz=256",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                             forHTTPHeaderField: "User-Agent")
            let semaphore = DispatchSemaphore(value: 0)
            var result: Data? = nil
            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let data = data, data.count > 200,
                   let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
                semaphore.signal()
            }.resume()
            semaphore.wait()
            if let data = result { return data }
        }
        return nil
    }
}
