import Foundation

struct SessionSnapshot: Codable {
    struct Entry: Codable {
        var url: URL?
        var title: String
        var pinned: Bool? = nil
        var favoriteID: UUID? = nil
    }
    var entries: [Entry]
    var selectedIndex: Int
    var version: Int? = nil
    var splitIndices: [Int]? = nil
    var splitStacked: Bool? = nil
    var windowFrame: String? = nil
    var wasActiveWindow: Bool? = nil

    var restoredSelectedIndex: Int? {
        entries.isEmpty ? nil : min(max(selectedIndex, 0), entries.count - 1)
    }

    /// Corrupt or stale pane references must not crash restoration or duplicate views.
    var restoredSplitIndices: [Int] {
        var seen = Set<Int>()
        let valid = (splitIndices ?? []).filter { entries.indices.contains($0) && seen.insert($0).inserted }
        return valid.count >= 2 ? Array(valid.prefix(4)) : []
    }
}

/// Persists open-tab URLs and the selected tab in UserDefaults.
final class SessionStore {
    private let key = "aero.session.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func save(_ snapshot: SessionSnapshot) {
        guard !snapshot.entries.isEmpty else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    func load() -> SessionSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              !snapshot.entries.isEmpty else { return nil }
        return snapshot
    }
}

/// Stores the open window set separately so older single-window sessions remain readable.
final class ApplicationSessionStore {
    private let defaults: UserDefaults
    private let key = "aero.windows.v1"
    private let fileURL: URL?
    private struct Archive: Codable {
        var version: Int
        var windows: [SessionSnapshot]
    }
    init(defaults: UserDefaults = .standard, fileURL: URL? = nil) {
        self.defaults = defaults
        self.fileURL = fileURL ?? (defaults === UserDefaults.standard
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Aero/Recovery/windows.json") : nil)
    }
    private func decode(_ data: Data) -> [SessionSnapshot]? {
        guard let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1 else { return nil }
        return archive.windows.filter { !$0.entries.isEmpty }
    }
    func save(_ windows: [SessionSnapshot]) {
        guard let data = try? JSONEncoder().encode(Archive(version: 1, windows: windows)) else { return }
        if let fileURL {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let previous = try? Data(contentsOf: fileURL), decode(previous) != nil {
                    try previous.write(to: fileURL.appendingPathExtension("backup"), options: .atomic)
                }
                try data.write(to: fileURL, options: .atomic)
            } catch { NSLog("Aero recovery write failed: %@", error.localizedDescription) }
        }
        defaults.set(data, forKey: key)
    }
    func load() -> [SessionSnapshot]? {
        if let fileURL {
            for candidate in [fileURL, fileURL.appendingPathExtension("backup")] {
                if let data = try? Data(contentsOf: candidate), let windows = decode(data) { return windows }
            }
        }
        return defaults.data(forKey: key).flatMap(decode)
    }
}
