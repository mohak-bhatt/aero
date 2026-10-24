import Combine
import Foundation
import WebKit

/// Single source of truth for the tab collection and the active tab.
@MainActor
final class TabManager: ObservableObject, TabHost {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var pinnedIDs: [UUID] = []
    /// favourite id -> id of the live tab that represents it (hidden from the tab list)
    @Published private(set) var favoriteTabs: [UUID: UUID] = [:]

    private var recentlyClosed: [URL] = []
    private var mru: [UUID] = []
    private let recentlyClosedLimit = 25

    var selectedTab: BrowserTab? { tabs.first { $0.id == selectedID } }

    var pinnedTabs: [BrowserTab] { pinnedIDs.compactMap { id in tabs.first { $0.id == id } } }
    var unpinnedTabs: [BrowserTab] {
        let hidden = Set(favoriteTabs.values)
        return tabs.filter { !pinnedIDs.contains($0.id) && !hidden.contains($0.id) }
    }

    // MARK: Favourite tabs

    func favoriteTab(for favorite: Favorite) -> BrowserTab? {
        guard let id = favoriteTabs[favorite.id] else { return nil }
        return tabs.first { $0.id == id }
    }

    func favoriteID(of tab: BrowserTab) -> UUID? {
        favoriteTabs.first { $0.value == tab.id }?.key
    }

    func registerFavoriteTab(_ tab: BrowserTab, for favorite: Favorite) {
        pinnedIDs.removeAll { $0 == tab.id }
        favoriteTabs[favorite.id] = tab.id
    }

    func releaseFavorite(id: UUID) {
        favoriteTabs.removeValue(forKey: id)
    }

    // MARK: Tab commands

    func duplicate(_ tab: BrowserTab) {
        newTab(url: tab.url, select: true, insertAfter: tab)
    }

    func closeOthers(except keep: BrowserTab) {
        for tab in tabs where tab.id != keep.id && !isPinned(tab) && favoriteID(of: tab) == nil {
            closeTab(tab)
        }
    }

    func selectNext() { cycleSelection(by: 1) }
    func selectPrevious() { cycleSelection(by: -1) }

    private func cycleSelection(by step: Int) {
        guard tabs.count > 1, let current = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        selectTab(tabs[(current + step + tabs.count) % tabs.count])
    }

    var recentlyClosedCount: Int { recentlyClosed.count }

    func isPinned(_ tab: BrowserTab) -> Bool { pinnedIDs.contains(tab.id) }

    func togglePin(_ tab: BrowserTab) {
        if let index = pinnedIDs.firstIndex(of: tab.id) {
            pinnedIDs.remove(at: index)
        } else {
            pinnedIDs.append(tab.id)
        }
    }

    // MARK: Reordering and moving between windows

    func move(_ tab: BrowserTab, to destination: BrowserTab) {
        guard tab.id != destination.id,
              let from = tabs.firstIndex(where: { $0.id == tab.id }),
              let to = tabs.firstIndex(where: { $0.id == destination.id }) else { return }
        let item = tabs.remove(at: from)
        tabs.insert(item, at: to)
    }

    /// Removes a tab without destroying its web view so another window can adopt it.
    @discardableResult
    func detach(_ tab: BrowserTab) -> BrowserTab? {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let wasSelected = tab.id == selectedID
        tabs.remove(at: index)
        pinnedIDs.removeAll { $0 == tab.id }
        favoriteTabs = favoriteTabs.filter { $0.value != tab.id }
        tab.host = nil
        if tabs.isEmpty {
            newTab()
        } else if wasSelected {
            selectTab(tabs[min(index, tabs.count - 1)])
        }
        return tab
    }

    func adopt(_ tab: BrowserTab) {
        tab.host = self
        tabs.append(tab)
        selectTab(tab)
    }

    // MARK: Creation

    @discardableResult
    func newTab(url: URL? = nil,
                configuration: WKWebViewConfiguration? = nil,
                select: Bool = true,
                insertAfter anchor: BrowserTab? = nil) -> BrowserTab {
        let tab = BrowserTab(url: url, configuration: configuration)
        tab.host = self
        if let anchor, let index = tabs.firstIndex(where: { $0.id == anchor.id }) {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        if select { selectTab(tab) }
        return tab
    }

    func restore(_ snapshot: SessionSnapshot) {
        guard !snapshot.entries.isEmpty else { return }
        let selected = min(max(snapshot.selectedIndex, 0), snapshot.entries.count - 1)
        for (index, entry) in snapshot.entries.enumerated() {
            let tab = BrowserTab(url: entry.url, title: entry.title, loadImmediately: index == selected)
            tab.host = self
            tabs.append(tab)
            if entry.pinned == true { pinnedIDs.append(tab.id) }
        }
        selectedID = tabs[selected].id
    }

    // MARK: Selection

    func mruTabs() -> [BrowserTab] {
        let ordered = mru.compactMap { id in tabs.first { $0.id == id } }
        return ordered + tabs.filter { tab in !mru.contains(tab.id) }
    }

    func selectTab(_ tab: BrowserTab) {
        if let previous = selectedTab, previous.id != tab.id { previous.captureSnapshot() }
        selectedID = tab.id
        mru.removeAll { $0 == tab.id }
        mru.insert(tab.id, at: 0)
        tab.activate()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectTab(tabs[index])
    }

    func selectLastTab() {
        if let last = tabs.last { selectTab(last) }
    }

    // MARK: Closing

    func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if let url = tab.url, url.scheme != "about" {
            recentlyClosed.append(url)
            if recentlyClosed.count > recentlyClosedLimit { recentlyClosed.removeFirst() }
        }
        let wasSelected = tab.id == selectedID
        tabs.remove(at: index)
        pinnedIDs.removeAll { $0 == tab.id }
        favoriteTabs = favoriteTabs.filter { $0.value != tab.id }
        tab.tearDown()

        if tabs.isEmpty {
            newTab()
        } else if wasSelected {
            selectTab(tabs[min(index, tabs.count - 1)])
        }
    }

    func closeSelectedTab() {
        if let tab = selectedTab { closeTab(tab) }
    }

    func reopenClosedTab() {
        guard let url = recentlyClosed.popLast() else { return }
        newTab(url: url)
    }

    // MARK: Session

    func snapshot() -> SessionSnapshot {
        let entries = tabs.compactMap { tab -> SessionSnapshot.Entry? in
            guard let url = tab.url, !favoriteTabs.values.contains(tab.id) else { return nil }
            return .init(url: url, title: tab.title, pinned: pinnedIDs.contains(tab.id))
        }
        let selected = tabs.filter { $0.url != nil && !favoriteTabs.values.contains($0.id) }.firstIndex { $0.id == selectedID } ?? 0
        return SessionSnapshot(entries: entries, selectedIndex: selected)
    }

    // MARK: TabHost

    func openInNewTab(_ url: URL, select: Bool, from tab: BrowserTab) {
        newTab(url: url, select: select, insertAfter: tab)
    }

    func openPopup(configuration: WKWebViewConfiguration, from tab: BrowserTab) -> BrowserTab {
        newTab(configuration: configuration, select: true, insertAfter: tab)
    }
}
