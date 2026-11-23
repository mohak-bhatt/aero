import Foundation

/// First Aero Engine configuration: data controls the existing native chrome.
struct BrowserLayout: Codable, Equatable {
    enum Preset: String, Codable, CaseIterable, Identifiable {
        case classic, focus, compact, horizontal, compactHorizontal
        var isHorizontal: Bool { self == .horizontal || self == .compactHorizontal }
        static var shippingCases: [Preset] { [.classic, .focus, .compact] }
        var id: String { rawValue }
        var title: String { switch self { case .classic: "Classic"; case .focus: "Focus"; case .compact: "Compact Vertical"; case .horizontal: "Horizontal"; case .compactHorizontal: "Compact Horizontal" } }
    }
    var version = 1
    var preset: Preset = .classic
    var sidebarWidth: Double = 270
    var sidebarPinned = true

    static func configuration(for preset: Preset) -> BrowserLayout {
        BrowserLayout(preset: preset, sidebarPinned: preset != .focus && !preset.isHorizontal)
    }
    /// A small overshoot prevents a resize at the normal minimum from collapsing the rail.
    static func shouldCollapse(proposedWidth: Double, minimumWidth: Double) -> Bool {
        proposedWidth.isFinite && proposedWidth < minimumWidth - 16
    }
    func validated() -> BrowserLayout {
        guard version == 1 else { return BrowserLayout() }
        var copy = self
        if copy.preset.isHorizontal { copy.preset = .classic; copy.sidebarPinned = true }
        copy.sidebarWidth = sidebarWidth.isFinite ? min(max(sidebarWidth, 200), 420) : 270
        return copy
    }
}

final class BrowserLayoutStore {
    private let defaults: UserDefaults
    private let key = "aero.engine.layout.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> BrowserLayout? {
        guard let data = defaults.data(forKey: key),
              let layout = try? JSONDecoder().decode(BrowserLayout.self, from: data) else { return nil }
        return layout.validated()
    }
    func save(_ layout: BrowserLayout) {
        guard let data = try? JSONEncoder().encode(layout.validated()) else { return }
        defaults.set(data, forKey: key)
    }
}
