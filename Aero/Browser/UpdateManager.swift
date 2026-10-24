import AppKit
import Combine

struct ReleaseInfo: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let assetURL: URL?
}

/// Checks GitHub Releases for a newer build and can replace the running app with it.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    ///
    nonisolated static let repo = "mohak-bhatt/aero"

    enum Status: Equatable { case idle, checking, upToDate, available, installing, failed(String) }
    private enum Failure: Error { case noApp, commandFailed }

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

    /// Downloads the release zip, swaps the app bundle once Aero quits, and relaunches.
    /// Falls back to opening the release page if the app can't replace itself (e.g. sandboxed).
    func install() {
        guard let release, status == .available else { return }
        guard let asset = release.assetURL else { NSWorkspace.shared.open(release.pageURL); return }
        status = .installing
        Task {
            do {
                let (downloaded, _) = try await URLSession.shared.download(from: asset)
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("AeroUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("Aero.zip")
                try FileManager.default.moveItem(at: downloaded, to: zip)
                try await Task.detached { try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) }.value

                guard let app = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                    .first(where: { $0.pathExtension == "app" }) else { throw Failure.noApp }

                let target = Bundle.main.bundleURL.path
                let script = work.appendingPathComponent("update.sh")
                let body = """
                #!/bin/sh
                while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
                rm -rf "\(target)"
                cp -R "\(app.path)" "\(target)"
                xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
                open "\(target)"
                """
                try body.write(to: script, atomically: true, encoding: .utf8)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [script.path]
                try process.run()
                NSApp.terminate(nil)
            } catch {
                status = .available
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw Failure.commandFailed }
    }

    nonisolated static func fetchLatest() async throws -> ReleaseInfo? {
        // /releases (not /releases/latest) so alpha pre-releases count too.
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=1") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = list.first,
              let tag = first["tag_name"] as? String,
              let page = (first["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = first["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        return ReleaseInfo(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                           notes: first["body"] as? String ?? "", pageURL: page, assetURL: zip)
    }
}
