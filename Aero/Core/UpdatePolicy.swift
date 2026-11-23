import Foundation

enum UpdatePolicy {
    nonisolated static func isTrustedReleasePage(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "github.com", url.user == nil,
              url.password == nil, url.port == nil || url.port == 443 else { return false }
        let parts = url.path.split(separator: "/")
        return parts.count == 5 && parts[0] == "mohak-bhatt" && parts[1] == "aero"
            && parts[2] == "releases" && parts[3] == "tag" && !parts[4].isEmpty
    }
}
