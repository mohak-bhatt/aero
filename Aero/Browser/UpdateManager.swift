import AppKit
import Combine

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let assetURL: URL?
}

/// Checks GitHub Releases and opens the trusted release page for manual updates.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    /// ⚠️ Set this to the GitHub "owner/repo" that publishes your releases.
    nonisolated static let repo = "mohak-bhatt/aero"

    enum Status: Equatable { case idle, checking, upToDate, available, installing, failed(String) }

    @Published private(set) var status: Status = .idle
    @Published private(set) var release: ReleaseInfo?
    private let lastCheckKey = "aero.lastUpdateCheck"

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var buildNumber: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }

    func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        if Date().timeIntervalSince1970 - last > 6 * 3600 { check(userInitiated: false) }
    }

    func check(userInitiated: Bool) {
        guard status != .checking, status != .installing else { return }
        guard !Self.repo.hasPrefix("YOUR-") else {
            if userInitiated { status = .failed("Set UpdateManager.repo to your GitHub owner/repo first.") }
            return
        }
        status = .checking
        Task {
            do {
                let info = try await Self.fetchLatest()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                if let info, info.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                    release = info
                    status = .available
                } else {
                    release = nil
                    status = .upToDate
                }
            } catch {
                status = userInitiated ? .failed("Couldn't reach GitHub. Check your connection.") : .idle
            }
        }
    }

    /// Manual updates until a signed, verified installer with rollback is integrated.
    func install() {
        guard let release, status == .available,
              UpdatePolicy.isTrustedReleasePage(release.pageURL) else { return }
        NSWorkspace.shared.open(release.pageURL)
    }

    nonisolated static func fetchLatest() async throws -> ReleaseInfo? {
        // /releases (not /releases/latest) so alpha pre-releases count too.
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=1") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = list.first,
              let tag = first["tag_name"] as? String,
              let page = (first["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        guard UpdatePolicy.isTrustedReleasePage(page) else { throw URLError(.badURL) }
        let assets = first["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                           notes: first["body"] as? String ?? "", pageURL: page, assetURL: zip)
    }
}
