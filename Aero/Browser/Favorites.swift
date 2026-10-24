import AppKit
import Combine

/// A saved page shown in the favourites box (bookmark-like, independent of open tabs).
struct Favorite: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var title: String
    var iconPNG: Data?
}

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var items: [Favorite] = [] {
        didSet { save() }
    }

    private let key = "aero.favorites.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = decoded
        }
    }

    /// Creates a favourite from a tab (http/https pages only).
    @discardableResult
    func add(from tab: BrowserTab) -> Favorite? {
        guard let url = tab.url, url.scheme?.hasPrefix("http") == true else { return nil }
        let favorite = Favorite(url: url, title: tab.displayTitle, iconPNG: Self.png(from: tab.favicon))
        items.append(favorite)
        return favorite
    }

    func remove(_ favorite: Favorite) {
        items.removeAll { $0.id == favorite.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func png(from image: NSImage?) -> Data? {
        guard let tiff = image?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
