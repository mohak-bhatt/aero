import SwiftUI

/// Right-click menu for any tab (sidebar row or pinned tile).
struct TabContextMenu: View {
    @EnvironmentObject var state: BrowserState
    @ObservedObject var tab: BrowserTab

    var body: some View {
        let tabs = state.tabs
        let favorite = tabs.favoriteID(of: tab) != nil
        let web = tab.url?.scheme?.hasPrefix("http") == true

        Button(tabs.isPinned(tab) ? "Unpin Tab" : "Pin Tab") { tabs.togglePin(tab) }.disabled(favorite)
        Button(favorite ? "Remove from Favorites" : "Add to Favorites") { state.toggleFavorite(tab) }.disabled(!web)
        Button("Add Bookmark…") { state.addBookmark(for: tab) }.disabled(!web)
        Divider()
        Button("Split with Current Tab") { if let anchor = tabs.selectedTab { tabs.split(tab, with: anchor) } }
            .disabled(tab.id == tabs.selectedID)
        if tabs.isInSplit(tab) { Button("Remove from Split View") { tabs.removeFromSplit(tab) } }
        Button("Reload Tab") { tab.reload() }
        Button("Duplicate Tab") { tabs.duplicate(tab) }
        Button("Copy Link") {
            if let url = tab.url {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
        .disabled(tab.url == nil)
        Divider()
        Button("Close Tab") { tabs.closeTab(tab) }
        Button("Close Other Tabs") { tabs.closeOthers(except: tab) }
        Button("Close Tabs Above") { tabs.closeTabs(before: tab) }
        Button("Close Tabs Below") { tabs.closeTabs(after: tab) }
        Button("Move Tab to New Window") { state.moveTabToNewWindow(tab) }.disabled(tabs.tabs.count < 2)
        Menu("Arrange Tabs By") {
            Button("Title") { tabs.arrange(by: .title) }
            Button("Website") { tabs.arrange(by: .website) }
        }
        Divider()
        Button("Reopen Closed Tab") { state.reopenClosedTab() }.disabled(tabs.recentlyClosedCount == 0)
    }
}

/// Right-click menu for empty space in the sidebar.
struct BackgroundContextMenu: View {
    @EnvironmentObject var state: BrowserState

    var body: some View {
        Button("New Tab") { state.newTab() }
        Button("New Window") { WindowCoordinator.shared.openWindow() }
        Button("Reopen Closed Tab") { state.reopenClosedTab() }.disabled(state.tabs.recentlyClosedCount == 0)
        Divider()
        Menu("Arrange Tabs By") {
            Button("Title") { state.tabs.arrange(by: .title) }
            Button("Website") { state.tabs.arrange(by: .website) }
        }
        Button("Close All Tabs") { state.tabs.closeAll() }
        Divider()
        Button("Add Bookmark…") { state.addBookmarkForCurrentTab() }
        Button("New Bookmark Folder…") { state.newBookmarkFolder() }
        Divider()
        Button("Hide Sidebar") { state.sidebarVisible = false; state.sidebarPeeking = false }
        Menu("Sidebar Size") {
            ForEach([("Automatic", 0), ("Small", 1), ("Medium", 2), ("Large", 3)], id: \.1) { item in
                Button(item.0) { state.sidebarSizeChoice = item.1 }
            }
        }
    }
}
