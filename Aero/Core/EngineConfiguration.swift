import Foundation
import Combine

/// Edge-only placement keeps controls out of page content. IDs survive preset changes.
struct EngineConfiguration: Codable, Equatable {
    enum Dock: String, Codable, CaseIterable, Identifiable {
        case left, right, top, bottom, hidden
        var id: String { rawValue }
        var vertical: Bool { self == .left || self == .right }
        var title: String { rawValue.capitalized }
    }
    enum Element: String, Codable, CaseIterable, Identifiable {
        case sidebar, back, forward, address, reload, pageMenu, favorites, pins, tabs, newTab, activities, downloads, bookmarks, share, history, settings, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sidebar: "Layout"; case .back: "Back"; case .forward: "Forward"
            case .address: "Address"; case .reload: "Reload"; case .pageMenu: "Page menu"
            case .favorites: "Favourites"; case .pins: "Pinned tabs"; case .tabs: "Tabs"
            case .newTab: "New tab"; case .activities: "Live Activities"; case .downloads: "Downloads"
            case .updates: "Updates"
            case .bookmarks: "Bookmarks"; case .share: "Share"; case .history: "History"; case .settings: "Settings"
            }
        }
        var symbol: String {
            switch self {
            case .sidebar: "sidebar.left"; case .back: "chevron.left"; case .forward: "chevron.right"
            case .address: "magnifyingglass"; case .reload: "arrow.clockwise"; case .pageMenu: "line.3.horizontal.decrease"
            case .favorites: "star"; case .pins: "pin"; case .tabs: "rectangle.on.rectangle"
            case .newTab: "plus"; case .activities: "waveform"; case .downloads: "arrow.down.circle"
            case .updates: "arrow.down.circle.fill"
            case .bookmarks: "book"; case .share: "square.and.arrow.up"; case .history: "clock"; case .settings: "gearshape"
            }
        }
    }
    struct Placement: Codable, Equatable, Identifiable {
        var element: Element
        var dock: Dock
        var large = false
        var id: Element { element }
    }
    var version = 1
    var compact = false
    var primary: Dock = .left
    var placements: [Placement] = []
    static func preset(_ dock: Dock = .left, compact: Bool = false) -> Self {
        let edge = dock == .hidden ? Dock.left : dock
        let elements = edge.vertical ? Element.allCases : [.tabs] + Element.allCases.filter { $0 != .tabs }
        return Self(compact: compact, primary: edge, placements: elements.map {
            Placement(element: $0, dock: [.history, .settings].contains($0) ? .hidden : edge)
        })
    }
    func validated() -> Self {
        guard version == 1 else { return .preset() }
        var result = self
        if result.primary == .hidden { result.primary = .left }
        var seen = Set<Element>()
        result.placements = placements.filter { seen.insert($0.element).inserted }
        for element in Element.allCases where !seen.contains(element) {
            result.placements.append(Placement(element: element, dock: .hidden))
        }
        // Always preserve a route to navigation and customization.
        for element in [Element.address, .tabs, .sidebar] {
            if let index = result.placements.firstIndex(where: { $0.element == element }), result.placements[index].dock == .hidden {
                result.placements[index].dock = result.primary
            }
        }
        return result
    }
    mutating func move(_ element: Element, to dock: Dock, before target: Element? = nil) {
        guard let index = placements.firstIndex(where: { $0.element == element }), target != element else { return }
        var item = placements.remove(at: index); item.dock = dock
        if let target, let targetIndex = placements.firstIndex(where: { $0.element == target }) { placements.insert(item, at: targetIndex) }
        else { placements.append(item) }
        self = validated()
    }
}

@MainActor final class EngineModel: ObservableObject {
    private let defaults: UserDefaults
    private let key = "aero.engine.elements.v1"
    @Published private(set) var configuration: EngineConfiguration
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "aero.engine.enabled") } }
    @Published private(set) var undoStack: [EngineConfiguration] = []
    @Published private(set) var redoStack: [EngineConfiguration] = []
    private var original: EngineConfiguration?
    private var originallyEnabled = false
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "aero.engine.enabled")
        configuration = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(EngineConfiguration.self, from: $0) }?.validated() ?? .preset()
    }
    func begin() {
        guard original == nil else { return }
        original = configuration; originallyEnabled = enabled; enabled = true
        undoStack = []; redoStack = []
    }
    func finish(cancel: Bool = false) {
        if cancel, let original { configuration = original; enabled = originallyEnabled; save() }
        original = nil; undoStack = []; redoStack = []
    }
    func update(_ operation: (inout EngineConfiguration) -> Void) {
        var next = configuration; operation(&next); next = next.validated()
        guard next != configuration else { return }
        undoStack.append(configuration); if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack = []; configuration = next; save()
    }
    func undo() { guard let last = undoStack.popLast() else { return }; redoStack.append(configuration); configuration = last; save() }
    func redo() { guard let last = redoStack.popLast() else { return }; undoStack.append(configuration); configuration = last; save() }
    private func save() { if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: key) } }
}
