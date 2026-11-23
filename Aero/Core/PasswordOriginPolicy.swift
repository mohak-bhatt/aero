import Foundation

/// Legacy Keychain entries are host-only. Restrict them to exact hosts on standard HTTPS.
enum PasswordOriginPolicy {
    static func trustedHost(pageURL: URL?, frameURL: URL?, isMainFrame: Bool,
                            originScheme: String, originHost: String, originPort: Int) -> String? {
        guard isMainFrame, let pageURL, let frameURL,
              pageURL.scheme?.lowercased() == "https", frameURL.scheme?.lowercased() == "https",
              originScheme.lowercased() == "https",
              (pageURL.port ?? 443) == 443, (frameURL.port ?? 443) == 443,
              originPort == 0 || originPort == 443,
              let host = pageURL.host?.lowercased(), !host.isEmpty,
              frameURL.host?.lowercased() == host, originHost.lowercased() == host,
              pageURL == frameURL else { return nil }
        return host
    }

    static func matchesCredential(requestHost: String, credentialHost: String) -> Bool {
        !requestHost.isEmpty && requestHost.lowercased() == credentialHost.lowercased()
    }
}
