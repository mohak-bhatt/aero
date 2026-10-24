import AppKit
import Combine
import WebKit

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckDuckGo, bing, ecosia
    var id: String { rawValue }
    var name: String {
        switch self { case .google: return "Google"; case .duckDuckGo: return "DuckDuckGo"
                      case .bing: return "Bing"; case .ecosia: return "Ecosia" }
    }
    var searchBase: String {
        switch self {
        case .google: return "https://www.google.com/search"
        case .duckDuckGo: return "https://duckduckgo.com/"
        case .bing: return "https://www.bing.com/search"
        case .ecosia: return "https://www.ecosia.org/search"
        }
    }
}

enum Pref {
    static let domainOnlyKey = "aero.domainOnly"
    static let engineKey = "aero.searchEngine"
    static let defaultZoomKey = "aero.defaultZoom"
    static let rememberZoomKey = "aero.rememberZoom"
    static let tintKey = "aero.tintSidebar"
    static let sugHistoryKey = "aero.sug.history"
    static let sugTabsKey = "aero.sug.tabs"
    static let sugBookmarksKey = "aero.sug.bookmarks"
    static let sugWebKey = "aero.sug.web"
    static let barKey = "aero.bookmarksBar"
    static let layoutKey = "aero.layout"
    static let blurKey = "aero.blur"
    static let sidebarSizeKey = "aero.sidebarSize"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
    static var engine: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .google
    }
}

/// Remembers the zoom level of every site, plus a default for new sites.
@MainActor
final class SiteZoomStore: ObservableObject {
    static let shared = SiteZoomStore()
    private let key = "aero.siteZooms.v1"

    @Published private(set) var zooms: [String: Double] = [:] {
        didSet { UserDefaults.standard.set(zooms, forKey: key) }
    }

    private init() { zooms = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }

    var defaultZoom: Double {
        let value = UserDefaults.standard.double(forKey: Pref.defaultZoomKey)
        return value > 0 ? value : 1
    }

    func zoom(for host: String?) -> Double {
        guard let host else { return defaultZoom }
        return zooms[host] ?? defaultZoom
    }

    func set(_ value: Double, for host: String?) {
        guard let host else { return }
        if abs(value - defaultZoom) < 0.001 { zooms.removeValue(forKey: host) } else { zooms[host] = value }
    }

    func remove(host: String) { zooms.removeValue(forKey: host) }
    func removeAll() { zooms = [:] }
}

enum WebsiteData {
    static func clearAll() {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                modifiedSince: .distantPast) {}
    }
}

@MainActor
enum Prompt {
    static func text(title: String, message: String = "", initial: String = "", button: String = "OK") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    static func confirm(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func info(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}


enum DefaultBrowser {
    static var isDefault: Bool {
        guard let url = URL(string: "https://example.com"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return app == Bundle.main.bundleURL
    }

    static func makeDefault() {
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme) { _ in }
        }
    }
}
