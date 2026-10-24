import Foundation

struct SessionSnapshot: Codable {
    struct Entry: Codable {
        var url: URL
        var title: String
        var pinned: Bool? = nil
    }
    var entries: [Entry]
    var selectedIndex: Int
}

/// Persists open-tab URLs and the selected tab in UserDefaults.
final class SessionStore {
    private let key = "aero.session.v1"

    func save(_ snapshot: SessionSnapshot) {
        guard !snapshot.entries.isEmpty, let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> SessionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              !snapshot.entries.isEmpty else { return nil }
        return snapshot
    }
}
