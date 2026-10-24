import SwiftUI

struct WindowView: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var tabs: TabManager

    init(state: BrowserState) {
        self.state = state
        self.tabs = state.tabs
    }

    var body: some View {
        Group {
            switch state.layout {
            case .horizontal: horizontalLayout
            case .vertical: verticalLayout
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .overlayPreferenceValue(OmniboxFrameKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, !state.suggestions.isEmpty {
                    let rect = proxy[anchor]
                    SuggestionsView(state: state)
                        .frame(width: rect.width)
                        .offset(x: rect.minX, y: rect.maxY + 6)
                }
            }
        }
        .overlay {
            if state.switcherShowing { TabSwitcherView(state: state) }
        }
    }

    // MARK: Horizontal: tabs on top, address toolbar below, bookmarks bar

    private var horizontalLayout: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                TabStripView(state: state, manager: tabs)
                if let tab = tabs.selectedTab { BrowserToolbar(tab: tab, state: state) }
                if state.showBookmarksBar { BookmarksBar(state: state, favorites: state.favorites, store: state.bookmarks, tabs: tabs) }
            }
            .background(ChromeBackground())
            .zIndex(2)

            content(topInset: 10)
        }
    }

    // MARK: Vertical: pinned sidebar, or a hidden one that slides over on hover

    private var verticalLayout: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if state.sidebarVisible { Color.clear.frame(width: state.sidebarColumnWidth) }
                content(topInset: state.rowHeight + 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state.sidebarVisible || state.sidebarPeeking {
                SidebarView(tabs: tabs, state: state, isOverlay: !state.sidebarVisible)
                    .frame(width: state.sidebarColumnWidth)
                    .frame(maxHeight: .infinity)
                    .shadow(color: .black.opacity(state.sidebarVisible ? 0 : 0.35), radius: 16, x: 6)
                    .onHover { inside in
                        if !state.sidebarVisible && !inside { state.sidebarPeeking = false }
                    }
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            } else {
                Color.clear
                    .frame(width: 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { if $0 { state.sidebarPeeking = true } }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: state.sidebarVisible)
        .animation(.easeInOut(duration: 0.22), value: state.sidebarPeeking)
    }

    private func content(topInset: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if let tab = tabs.selectedTab {
                TabContentView(tab: tab, state: state)
            } else {
                NewTabView(state: state)
            }
            if state.findVisible {
                FindBarView(state: state).padding(.top, topInset).padding(.trailing, 14)
            }
        }
    }
}

private struct TabContentView: View {
    @ObservedObject var tab: BrowserTab
    let state: BrowserState

    var body: some View {
        if tab.url != nil || tab.isLoading {
            WebViewHost(webView: tab.webView).id(tab.id)
        } else {
            NewTabView(state: state)
        }
    }
}
