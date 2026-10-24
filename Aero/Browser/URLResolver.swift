import Foundation

/// Turns whatever the user typed into a URL: an address, or a search query.
enum URLResolver {

    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }

        if !text.contains(" ") {
            let hostPart = String(text.split(separator: "/", maxSplits: 1).first ?? "")
            let hostNoPort = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
            if hostNoPort.lowercased() == "localhost" || isIPv4(hostNoPort) {
                return URL(string: "http://" + text)
            }
            if looksLikeDomain(hostNoPort) {
                return URL(string: "https://" + text)
            }
        }
        return searchURL(for: text)
    }

    static func searchURL(for query: String) -> URL? {
        var components = URLComponents(string: Pref.engine.searchBase)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private static func looksLikeDomain(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last else { return false }
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter } && parts.allSatisfy { !$0.isEmpty }
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}

extension URL {
    /// Compact string shown in the omnibox when it isn't being edited.
    var omniboxDisplay: String {
        guard scheme == "http" || scheme == "https" else { return absoluteString }
        if Pref.bool(Pref.domainOnlyKey, default: true), let host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        var s = absoluteString
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
        if s.hasSuffix("/"), s.filter({ $0 == "/" }).count == 1 { s.removeLast() }
        return s
    }
}
