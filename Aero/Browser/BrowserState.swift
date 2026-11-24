import AppKit
import Combine
import SwiftUI
import WebKit

/// Mirrors the three macOS sidebar sizes (System Settings → Appearance).
enum SidebarSize: Int, CaseIterable {
    case small = 1, medium = 2, large = 3

    static func fromSystem() -> SidebarSize {
        SidebarSize(rawValue: UserDefaults.standard.integer(forKey: "NSTableViewDefaultSizeMode")) ?? .medium
    }
    private func pick(_ s: CGFloat, _ m: CGFloat, _ l: CGFloat) -> CGFloat {
        switch self { case .small: return s; case .medium: return m; case .large: return l }
    }
    var rowHeight: CGFloat { pick(28, 32, 38) }
    var font: CGFloat { pick(12, 12.5, 13.5) }
    var iconSize: CGFloat { pick(14, 15, 18) }
    var pinnedCell: CGFloat { pick(34, 40, 46) }
    var favoriteCell: CGFloat { pick(44, 50, 58) }
    var controlHeight: CGFloat { pick(34, 40, 46) }
    var pillHeight: CGFloat { pick(32, 36, 42) }
    var spacing: CGFloat { pick(8, 10, 12) }
    var hPad: CGFloat { pick(10, 12, 14) }
    /// Narrowest sidebar that still fits five pinned / four favourite tiles at full size.
    var minWidth: CGFloat { pick(232, 264, 300) }
}

struct TabDrag: Equatable {
    var tabID: UUID
    var location: CGPoint
    var overContent: Bool
    var placeLeft: Bool
}

struct HoverPreview: Equatable {
    let tabID: UUID
    /// Pointer height in window coordinates; the card sits beside the sidebar at that height.
    let y: CGFloat
}

enum SuggestionSource: String { case omnibox, home }

/// Per-window state: tabs, layout, sidebar, find, suggestions, tab switcher, session.
@MainActor
final class BrowserState: ObservableObject {
    let tabs = TabManager()
    let favorites = FavoritesStore.shared
    let bookmarks = BookmarkStore.shared
    let history = HistoryStore.shared
    let isPrimary: Bool
    weak var window: NSWindow?

    // Native title-bar metrics (measured by the window controller)
    @Published var isFullScreen = false
    @Published var titlebarHeight: CGFloat = 52
    @Published var trafficLightsTrailing: CGFloat = 70
    @Published var trafficLightGap: CGFloat = 8

    @Published var pendingOmniboxFocus = false
    @Published var findVisible = false
    @Published var findText = ""
    @Published var findNotFound = false
    @Published var findFocusToken = 0

    let engine = EngineModel()
    var engineContentRect: CGRect?
    var engineCompactLights: Bool { engine.enabled && engine.configuration.compact && engine.configuration.primary.vertical }
    @Published var engineEditing = false { didSet { if engineEditing { engine.begin() } } }
    @Published var activitiesDrawerOpen = false
    @Published var activitiesDragWidth: CGFloat? = nil
    var activitiesRevealWidth: CGFloat { activitiesDragWidth ?? (activitiesDrawerOpen ? 52 : 0) }
    @Published var layoutPreset: BrowserLayout.Preset = .classic
    @Published var sidebarVisible = true
    @Published var sidebarPeeking = false
    @Published var sidebarWidth: CGFloat
    @Published var bookmarksOpen = false
    @Published var drag: TabDrag?
    @Published var hoverPreview: HoverPreview?
    var tornOff = false
    private var tearMonitor: Any?
    @Published var sidebarSizeChoice: Int {
        didSet { UserDefaults.standard.set(sidebarSizeChoice, forKey: Pref.sidebarSizeKey) }
    }
    @Published private var systemSidebarSize: SidebarSize

    // Address-bar suggestions
    @Published var suggestions: [Suggestion] = []
    @Published var suggestionIndex: Int?
    @Published var suggestionSource: SuggestionSource = .omnibox
    var suggestTask: Task<Void, Never>?
    var suggestionQuery = ""

    // Ctrl+Tab switcher
    @Published var switcherActive = false
    @Published var switcherShowing = false
    @Published var switcherIndex = 0
    @Published var switcherTabs: [BrowserTab] = []

    private let store = SessionStore()
    private var cancellables = Set<AnyCancellable>()

    var sidebarSize: SidebarSize { SidebarSize(rawValue: sidebarSizeChoice) ?? systemSidebarSize }
    var rowHeight: CGFloat { isFullScreen ? 44 : titlebarHeight }
    /// x where the sidebar / layout toggle starts: one traffic-light gap after the green button.
    var leadingInset: CGFloat { isFullScreen ? 12 : trafficLightsTrailing + trafficLightGap }
    var sidebarColumnWidth: CGFloat { layoutPreset == .compact ? 52 : min(max(sidebarWidth, sidebarSize.minWidth), 420) }

    init(initialTab: BrowserTab? = nil, isPrimary: Bool = false, restoredSession: SessionSnapshot? = nil) {
        self.isPrimary = isPrimary
        let defaults = UserDefaults.standard
        let savedWidth = defaults.double(forKey: "aero.sidebarWidth")
        sidebarWidth = savedWidth >= 200 ? savedWidth : 270
        sidebarSizeChoice = defaults.integer(forKey: Pref.sidebarSizeKey)
        systemSidebarSize = SidebarSize.fromSystem()
        if let layout = BrowserLayoutStore().load() {
            layoutPreset = layout.preset
            sidebarWidth = layout.sidebarWidth
            sidebarVisible = layout.sidebarPinned
        }

        if let snapshot = restoredSession {
            tabs.restore(snapshot)
        } else if isPrimary, let snapshot = store.load() {
            tabs.restore(snapshot)
        } else if let initialTab {
            tabs.adopt(initialTab)
        } else {
            tabs.newTab()
            pendingOmniboxFocus = true
        }

        bindSessionSaving()
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.systemSidebarSize = SidebarSize.fromSystem() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncPrefs() }
            .store(in: &cancellables)
    }

    private func syncPrefs() {
        let defaults = UserDefaults.standard
        let choice = defaults.integer(forKey: Pref.sidebarSizeKey)
        if choice != sidebarSizeChoice { sidebarSizeChoice = choice }
    }

    // MARK: Basic actions

    func newTab() { tabs.newTab(); requestOmniboxFocus() }
    func closeSelectedTab() { tabs.closeSelectedTab() }
    func reopenClosedTab() { tabs.reopenClosedTab() }
    func requestOmniboxFocus() {
        if engine.enabled { sidebarVisible = true }
        if !sidebarVisible && !layoutPreset.isHorizontal { sidebarPeeking = true }
        pendingOmniboxFocus = true
    }

    func applyLayout(_ preset: BrowserLayout.Preset) {
        if engine.enabled {
            engine.update { configuration in
                configuration = .preset(preset.isHorizontal ? .top : .left,
                    compact: preset == .compact || preset == .compactHorizontal)
            }
            sidebarVisible = preset != .focus
            sidebarPeeking = false
            return
        }
        guard !preset.isHorizontal else { return }
        var layout = BrowserLayout.configuration(for: preset)
        layout.sidebarWidth = Double(sidebarWidth)
        layoutPreset = preset
        sidebarWidth = layout.sidebarWidth
        sidebarVisible = layout.sidebarPinned
        sidebarPeeking = false
        BrowserLayoutStore().save(layout)
    }

    func openURL(_ url: URL) {
        if let tab = tabs.selectedTab { tab.load(url) } else { tabs.newTab(url: url) }
    }

    func submit(_ text: String) {
        if let index = suggestionIndex, suggestions.indices.contains(index) { choose(suggestions[index]); return }
        clearSuggestions()
        guard let url = URLResolver.resolve(text) else { return }
        openURL(url)
    }

    func reloadOrStop(forceReload: Bool = false) {
        guard let tab = tabs.selectedTab else { return }
        if forceReload { tab.reload() } else { tab.reloadOrStop() }
    }

    func toggleSidebar() {
        sidebarVisible.toggle()
        sidebarPeeking = false
        persistLayout()
    }

    func toggleBookmarks() {
        if !sidebarVisible { sidebarVisible = true }
        bookmarksOpen.toggle()
    }

    private func persistLayout() {
        BrowserLayoutStore().save(BrowserLayout(preset: layoutPreset,
            sidebarWidth: Double(sidebarWidth), sidebarPinned: sidebarVisible))
    }

    func persistSidebarWidth() {
        UserDefaults.standard.set(Double(sidebarWidth), forKey: "aero.sidebarWidth")
        persistLayout()
    }

    // MARK: Favourites (live tabs shown as tiles, not in the tab list)

    func toggleFavorite(_ tab: BrowserTab) {
        if let id = tabs.favoriteID(of: tab) {
            tabs.releaseFavorite(id: id)
            if let favorite = favorites.items.first(where: { $0.id == id }) { favorites.remove(favorite) }
        } else if let favorite = favorites.add(from: tab) {
            tabs.registerFavoriteTab(tab, for: favorite)
        }
    }

    func removeFavorite(_ favorite: Favorite) {
        tabs.releaseFavorite(id: favorite.id)
        favorites.remove(favorite)
    }

    func openFavorite(_ favorite: Favorite) {
        if let existing = tabs.favoriteTab(for: favorite) {
            tabs.selectTab(existing)
        } else {
            let tab = tabs.newTab(url: favorite.url, select: true)
            tabs.registerFavoriteTab(tab, for: favorite)
        }
    }

    // MARK: Bookmarks

    func addBookmarkForCurrentTab(in folder: UUID? = nil) {
        guard let tab = tabs.selectedTab, let url = tab.url, url.scheme?.hasPrefix("http") == true else { return }
        guard let name = Prompt.text(title: "Add Bookmark", message: url.absoluteString,
                                     initial: tab.displayTitle, button: "Add") else { return }
        let icon = tab.favicon?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        bookmarks.addBookmark(title: name.isEmpty ? tab.displayTitle : name, url: url, icon: icon, to: folder)
    }

    func newBookmarkFolder(in folder: UUID? = nil) {
        if let name = Prompt.text(title: "New Bookmark Folder", initial: "New Folder", button: "Create"), !name.isEmpty {
            bookmarks.addFolder(title: name, to: folder)
        }
    }

    // MARK: Tab dragging (reorder, split view, tear-off)

    /// The page area in window coordinates (origin top-left).
    var contentRect: CGRect {
        if engine.enabled, let engineContentRect { return engineContentRect }
        guard let size = window?.contentView?.bounds.size else { return .zero }
        if layoutPreset.isHorizontal {
            let top = rowHeight + (layoutPreset == .compactHorizontal ? 8 : 54)
            return CGRect(x: 0, y: top, width: size.width, height: max(0, size.height - top))
        }
        let x = sidebarVisible ? sidebarColumnWidth + activitiesRevealWidth : 0
        return CGRect(x: x, y: 0, width: size.width - x, height: size.height)
    }

    func windowPoint(_ screen: NSPoint) -> CGPoint {
        guard let window, let content = window.contentView else { return .zero }
        let point = window.convertPoint(fromScreen: screen)
        return CGPoint(x: point.x, y: content.bounds.height - point.y)
    }

    func isOverContent(_ screen: NSPoint) -> Bool {
        guard let frame = window?.frame, frame.contains(screen) else { return false }
        let point = windowPoint(screen), rect = contentRect
        return point.x > rect.minX + 6 && point.y > rect.minY + 6
    }

    /// Called continuously while a tab is dragged. Leaving the window tears the tab off live.
    func dragMoved(_ tab: BrowserTab) {
        guard !tornOff, let frame = window?.frame else { return }
        // One tab: nothing to split with and nowhere to move it.
        guard tabs.tabs.count > 1 else { drag = nil; return }
        let screen = NSEvent.mouseLocation
        if !frame.insetBy(dx: -8, dy: -8).contains(screen) { beginTearOff(tab, at: screen); return }
        let point = windowPoint(screen)
        let over = isOverContent(screen)
        let rect = contentRect
        drag = TabDrag(tabID: tab.id, location: point, overContent: over,
                       placeLeft: over && point.x < rect.midX && tabs.selectedSplit == nil)
        hoverPreview = nil
    }

    /// Returns true if the drop was handled (split / tear-off) so the caller must not reorder.
    func dragEnded(_ tab: BrowserTab) -> Bool {
        let current = drag
        drag = nil
        if tornOff { return true }
        guard let current, current.overContent else { return false }
        let anchor: BrowserTab? = {
            if let selected = tabs.selectedTab, selected.id != tab.id { return selected }
            return tabs.mruTabs().first { $0.id != tab.id }
        }()
        if let anchor { tabs.split(tab, with: anchor, placeBefore: current.placeLeft) }
        return true
    }

    /// Opens the tab in a new window right away and keeps that window glued to the pointer.
    func beginTearOff(_ tab: BrowserTab, at screen: NSPoint) {
        guard !tornOff, tabs.tabs.count > 1, let moved = tabs.detach(tab) else { return }
        tornOff = true
        drag = nil
        let controller = WindowCoordinator.shared.openWindow(adopting: moved, near: screen)
        guard let newWindow = controller.window else { tornOff = false; return }
        tearMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self, weak newWindow] event in
            if event.type == .leftMouseDragged, let newWindow {
                let point = NSEvent.mouseLocation
                newWindow.setFrameTopLeftPoint(NSPoint(x: point.x - 120, y: point.y + 20))
            } else if event.type == .leftMouseUp {
                if let monitor = self?.tearMonitor { NSEvent.removeMonitor(monitor) }
                self?.tearMonitor = nil
                self?.tornOff = false
            }
            return event
        }
    }

    func addBookmark(for tab: BrowserTab, in folder: UUID? = nil) {
        guard let url = tab.url, url.scheme?.hasPrefix("http") == true,
              let name = Prompt.text(title: "Add Bookmark", message: url.absoluteString, initial: tab.displayTitle, button: "Add") else { return }
        let icon = tab.favicon?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        bookmarks.addBookmark(title: name.isEmpty ? tab.displayTitle : name, url: url, icon: icon, to: folder)
    }

    func moveTabToNewWindow(_ tab: BrowserTab) {
        let frame = window?.frame ?? .zero
        tearOff(tab, at: NSPoint(x: frame.midX, y: frame.midY))
    }

    func openBookmark(_ node: BookmarkNode, inNewTab: Bool) {
        guard let url = node.url else { return }
        if inNewTab { tabs.newTab(url: url) } else { openURL(url) }
    }

    func openAll(in folder: BookmarkNode) {
        for node in BookmarkStore.flatten(folder.children ?? []) { if let url = node.url { tabs.newTab(url: url, select: false) } }
    }

    // MARK: Find on Page

    func showFind() { findVisible = true; findFocusToken += 1 }

    func hideFind() {
        findVisible = false
        findNotFound = false
        tabs.selectedTab?.webView.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
    }

    func find(backwards: Bool) {
        guard let tab = tabs.selectedTab, !findText.isEmpty else { findNotFound = false; return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        configuration.caseSensitive = false
        tab.webView.find(findText, configuration: configuration) { [weak self] result in
            Task { @MainActor in self?.findNotFound = !result.matchFound }
        }
    }

    // MARK: Page commands

    func hardReload() { tabs.selectedTab?.webView.reloadFromOrigin() }
    func stopLoading() { tabs.selectedTab?.stop() }
    func closeWindow() { window?.performClose(nil) }
    func duplicateTab() { if let tab = tabs.selectedTab { tabs.duplicate(tab) } }
    func closeOtherTabs() { if let tab = tabs.selectedTab { tabs.closeOthers(except: tab) } }

    func moveSelectedTabToNewWindow() {
        guard let tab = tabs.selectedTab else { return }
        let frame = window?.frame ?? .zero
        tearOff(tab, at: NSPoint(x: frame.midX, y: frame.midY))
    }

    func tearOff(_ tab: BrowserTab, at screenPoint: NSPoint) {
        guard tabs.tabs.count > 1, let moved = tabs.detach(tab) else { return }
        WindowCoordinator.shared.openWindow(adopting: moved, near: screenPoint)
    }

    func setUserAgent(_ agent: String?) {
        guard let tab = tabs.selectedTab else { return }
        tab.webView.customUserAgent = agent
        tab.reload()
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tabs.newTab(url: url)
    }

    func savePage() {
        guard let tab = tabs.selectedTab else { return }
        let name = (tab.displayTitle.isEmpty ? "Page" : tab.displayTitle) + ".webarchive"
        tab.webView.createWebArchiveData { result in
            guard case .success(let data) = result else { return }
            Task { @MainActor in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name
                panel.begin { response in
                    if response == .OK, let url = panel.url { try? data.write(to: url) }
                }
            }
        }
    }

    func printPage() {
        guard let tab = tabs.selectedTab, let window else { return }
        let operation = tab.webView.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = tab.webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func viewSource() {
        guard let tab = tabs.selectedTab else { return }
        let host = tab.url?.host ?? "page"
        tab.webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let self, let html = result as? String else { return }
            Task { @MainActor in
                let page = """
                <!doctype html><meta charset="utf-8"><meta name="color-scheme" content="light dark">
                <title>Source of \(host)</title>
                <pre style="font: 12px ui-monospace, Menlo, monospace; white-space: pre-wrap; word-break: break-all; margin: 16px">\(Self.escape(html))</pre>
                """
                self.tabs.newTab().webView.loadHTMLString(page, baseURL: nil)
            }
        }
    }

    func showAllHistory() {
        var rows = ""
        for entry in history.entries.prefix(500) {
            rows += "<li><a href=\"\(entry.url.absoluteString)\">\(Self.escape(entry.title))</a> <small>\(Self.escape(entry.url.host ?? ""))</small></li>"
        }
        let page = """
        <!doctype html><meta charset="utf-8"><meta name="color-scheme" content="light dark"><title>History</title>
        <style>body{font:14px -apple-system,system-ui;max-width:760px;margin:40px auto;padding:0 20px}
        li{margin:6px 0;list-style:none}small{opacity:.55;margin-left:8px}a{text-decoration:none}</style>
        <h1>History</h1><ul style="padding:0">\(rows.isEmpty ? "<li>No history yet.</li>" : rows)</ul>
        """
        tabs.newTab().webView.loadHTMLString(page, baseURL: nil)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Website data

    func clearBrowsingData() {
        guard Prompt.confirm(title: "Clear all browsing data?",
                             message: "This removes history, cookies, caches and site data for every website.",
                             button: "Clear") else { return }
        history.clear()
        WebsiteData.clearAll()
    }

    func clearHistory() {
        if Prompt.confirm(title: "Clear history?", message: "Visited pages will be removed from history.", button: "Clear") {
            history.clear()
        }
    }

    func emptyCaches() {
        WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
                                                modifiedSince: .distantPast) {}
    }

    func clearWebsiteData(host: String) async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.fetchDataRecords(ofTypes: types) { records in
                let matches = records.filter { host == $0.displayName || host.hasSuffix("." + $0.displayName) }
                store.removeData(ofTypes: types, for: matches) { continuation.resume() }
            }
        }
    }

    // MARK: Ctrl+Tab switcher

    func switcherAdvance(backwards: Bool) {
        if !switcherActive {
            switcherTabs = tabs.mruTabs()
            guard switcherTabs.count > 1 else { return }
            switcherActive = true
            switcherIndex = 0
            tabs.selectedTab?.captureSnapshot()   // the visible tab; others were captured when left
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if self?.switcherActive == true { self?.switcherShowing = true }
            }
        }
        let count = switcherTabs.count
        switcherIndex = (switcherIndex + (backwards ? -1 : 1) + count) % count
    }

    func switcherCommit(select: Bool = true) {
        guard switcherActive else { return }
        if select, switcherTabs.indices.contains(switcherIndex) { tabs.selectTab(switcherTabs[switcherIndex]) }
        switcherActive = false
        switcherShowing = false
        switcherTabs = []
    }

    // MARK: Session

    func saveSession() {
        if isPrimary { store.save(tabs.snapshot()) }
        WindowCoordinator.shared.saveSessions()
    }

    private func bindSessionSaving() {
        let pageChanges = tabs.$tabs
            .map { tabs -> AnyPublisher<Void, Never> in
                Publishers.MergeMany(tabs.map { tab in
                    Publishers.Merge(tab.$url.map { _ in () }, tab.$title.map { _ in () })
                }).eraseToAnyPublisher()
            }
            .switchToLatest()
        let changes: [AnyPublisher<Void, Never>] = [
            pageChanges.eraseToAnyPublisher(),
            tabs.$selectedID.map { _ in () }.eraseToAnyPublisher(),
            tabs.$tabs.map { _ in () }.eraseToAnyPublisher(),
            tabs.$splitStacked.map { _ in () }.eraseToAnyPublisher(),
            tabs.$splitIDs.map { _ in () }.eraseToAnyPublisher(),
            tabs.$pinnedIDs.map { _ in () }.eraseToAnyPublisher(),
            tabs.$favoriteTabs.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(changes)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.saveSession() }
            .store(in: &cancellables)
    }
}
