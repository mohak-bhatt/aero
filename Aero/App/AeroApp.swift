import SwiftUI

@main
struct AeroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { SettingsView() }
            .commands { AeroCommands() }
    }
}

@MainActor
struct AeroCommands: Commands {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @ObservedObject private var favorites = FavoritesStore.shared

    private var state: BrowserState? { WindowCoordinator.shared.activeState }

    private static let agents: [(String, String?)] = [
        ("Default", nil),
        ("Safari — iPhone", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        ("Safari — iPad", "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        ("Chrome — macOS", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"),
        ("Firefox — macOS", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:132.0) Gecko/20100101 Firefox/132.0")
    ]

    private var otherBrowsers: [URL] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .filter { Bundle(url: $0)?.bundleIdentifier != Bundle.main.bundleIdentifier }
    }

    var body: some Commands {
        // MARK: App menu (Settings… comes from the Settings scene)
        CommandGroup(replacing: .appInfo) {
            Button("About Aero") { AboutWindow.show() }
            Button("Check for Updates…") {
                UpdateManager.shared.check(userInitiated: true)
                AboutWindow.show()
            }
        }
        CommandGroup(after: .appSettings) {
            Divider()
            Button("Clear History…") { state?.clearHistory() }
        }
        CommandGroup(after: .help) {
            Button("Welcome Tour…") { Onboarding.show() }
        }

        // MARK: File
        CommandGroup(replacing: .newItem) {
            Button("New Window") { WindowCoordinator.shared.openWindow() }.keyboardShortcut("n", modifiers: .command)
            Button("New Tab") { state?.newTab() }.keyboardShortcut("t", modifiers: .command)
            Button("Open File…") { state?.openFile() }.keyboardShortcut("o", modifiers: .command)
            Button("Open Location…") { state?.requestOmniboxFocus() }.keyboardShortcut("l", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Window") { state?.closeWindow() }.keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Close Tab") { state?.closeSelectedTab() }.keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Save Page As…") { state?.savePage() }.keyboardShortcut("s", modifiers: .command)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { state?.printPage() }.keyboardShortcut("p", modifiers: .command)
        }

        // MARK: Edit
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find on Page…") { state?.showFind() }.keyboardShortcut("f", modifiers: .command)
                Button("Find Next") { state?.find(backwards: false) }.keyboardShortcut("g", modifiers: .command)
                Button("Find Previous") { state?.find(backwards: true) }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        // MARK: View
        CommandGroup(after: .toolbar) {
            Button("Show or Hide Bookmarks Bar") { state?.toggleBookmarksBar() }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Use Vertical or Horizontal Tabs") { state?.toggleLayout() }.keyboardShortcut("v", modifiers: [.command, .option])
            Button("Show or Hide Sidebar") { state?.toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
            Menu("Sidebar Size") {
                ForEach([("Automatic", 0), ("Small", 1), ("Medium", 2), ("Large", 3)], id: \.1) { item in
                    Toggle(item.0, isOn: Binding(get: { state?.sidebarSizeChoice == item.1 },
                                                 set: { _ in state?.sidebarSizeChoice = item.1 }))
                }
            }
            Divider()
            Button("Stop") { state?.stopLoading() }.keyboardShortcut(".", modifiers: .command)
            Button("Reload Page") { state?.reloadOrStop(forceReload: true) }.keyboardShortcut("r", modifiers: .command)
            Button("Reload Ignoring Cache") { state?.hardReload() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Actual Size") { state?.tabs.selectedTab?.resetZoom() }.keyboardShortcut("0", modifiers: .command)
            Button("Zoom In") { state?.tabs.selectedTab?.zoomIn() }.keyboardShortcut("+", modifiers: .command)
            Button("Zoom In (⌘=)") { state?.tabs.selectedTab?.zoomIn() }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { state?.tabs.selectedTab?.zoomOut() }.keyboardShortcut("-", modifiers: .command)
        }

        // MARK: History
        CommandMenu("History") {
            Button("Show All History") { state?.showAllHistory() }.keyboardShortcut("y", modifiers: .command)
            Divider()
            Button("Back") { state?.tabs.selectedTab?.goBack() }.keyboardShortcut("[", modifiers: .command)
            Button("Forward") { state?.tabs.selectedTab?.goForward() }.keyboardShortcut("]", modifiers: .command)
            Button("Home") { state?.newTab() }.keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Reopen Last Closed Tab") { state?.reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            ForEach(history.recent(12)) { entry in
                Button(entry.title) { state?.openURL(entry.url) }
            }
            Divider()
            Button("Clear History…") { state?.clearHistory() }
            Button("Clear All Browsing Data…") { state?.clearBrowsingData() }.keyboardShortcut(.delete, modifiers: [.command, .shift])
        }

        // MARK: Bookmarks
        CommandMenu("Bookmarks") {
            Button("Show Bookmarks") { state?.toggleBookmarks() }.keyboardShortcut("b", modifiers: [.command, .option])
            Divider()
            Button("Add Bookmark…") { state?.addBookmarkForCurrentTab() }.keyboardShortcut("d", modifiers: .command)
            Button("Add Bookmark Folder…") { state?.newBookmarkFolder() }
            Button("Add to Favorites") {
                if let tab = state?.tabs.selectedTab { state?.toggleFavorite(tab) }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Menu("Favorites") {
                if favorites.items.isEmpty { Text("No favorites") }
                ForEach(favorites.items) { favorite in Button(favorite.title) { state?.openFavorite(favorite) } }
            }
            Divider()
            BookmarkMenuItems(nodes: bookmarks.items) { state?.openBookmark($0, inNewTab: false) }
        }

        // MARK: Develop
        CommandMenu("Develop") {
            Menu("Open Page With") {
                ForEach(otherBrowsers, id: \.self) { app in
                    Button(FileManager.default.displayName(atPath: app.path)) {
                        if let url = state?.tabs.selectedTab?.url {
                            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                        }
                    }
                }
            }
            Menu("User Agent") {
                ForEach(Self.agents, id: \.0) { agent in Button(agent.0) { state?.setUserAgent(agent.1) } }
            }
            Divider()
            Button("Show Page Source") { state?.viewSource() }.keyboardShortcut("u", modifiers: [.command, .option])
            Button("Empty Caches") { state?.emptyCaches() }.keyboardShortcut("e", modifiers: [.command, .option])
            Text("Right-click a page → Inspect Element")
        }

        // MARK: Window (tab commands live here, like Safari)
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Previous Tab") { state?.tabs.selectPrevious() }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Show Next Tab") { state?.tabs.selectNext() }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Pin or Unpin Tab") {
                if let tab = state?.tabs.selectedTab { state?.tabs.togglePin(tab) }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Duplicate Tab") { state?.duplicateTab() }
            Button("Move Tab to New Window") { state?.moveSelectedTabToNewWindow() }
            Button("Merge All Windows") { if let state { WindowCoordinator.shared.mergeAll(into: state) } }
            Button("Close Other Tabs") { state?.closeOtherTabs() }.keyboardShortcut("w", modifiers: [.command, .option])
            Divider()
            ForEach(1...8, id: \.self) { n in
                Button("Show Tab \(n)") { state?.tabs.selectTab(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("Show Last Tab") { state?.tabs.selectLastTab() }.keyboardShortcut("9", modifiers: .command)
            Divider()
            Button("Show Downloads in Finder") { DownloadManager.shared.showInFinder() }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
    }
}
