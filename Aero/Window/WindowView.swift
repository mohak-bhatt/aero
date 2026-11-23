import SwiftUI

struct WindowView: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var tabs: TabManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(state: BrowserState) {
        self.state = state
        self.tabs = state.tabs
    }

    var body: some View {
        Group {
            if state.layoutPreset.isHorizontal { horizontalLayout } else { verticalLayout }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if !state.layoutPreset.isHorizontal { EngineDock(state: state, edge: "top") } }
        .safeAreaInset(edge: .bottom, spacing: 0) { if !state.layoutPreset.isHorizontal { EngineDock(state: state, edge: "bottom") } }
        .overlay { if state.engineEditing { EngineCanvas(state: state) } }
        .ignoresSafeArea(.container, edges: .top)
        .environmentObject(state)
        .overlayPreferenceValue(OmniboxFrameKey.self) { anchors in
            GeometryReader { proxy in
                // The list opens under whichever field the user is typing in.
                if let anchor = anchors[state.suggestionSource.rawValue], !state.suggestions.isEmpty {
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
        .overlay { DragOverlay(state: state, tabs: tabs) }
        .overlay { HoverPreviewOverlay(state: state, tabs: tabs) }
        .coordinateSpace(name: "aeroWindow")
    }

    private var horizontalLayout: some View {
        VStack(spacing: 0) {
            if let tab = tabs.selectedTab {
                HorizontalChrome(state: state, tabs: tabs, tab: tab, favorites: state.favorites)
            }
            content(topInset: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    if state.sidebarVisible || state.sidebarPeeking {
                        SidebarView(tabs: tabs, state: state, isOverlay: true)
                            .frame(width: state.sidebarColumnWidth + state.activitiesRevealWidth)
                    }
                }
        }
    }

    // MARK: Vertical: pinned sidebar, or a hidden one that slides over on hover

    private var verticalLayout: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if state.sidebarVisible { Color.clear.frame(width: state.sidebarColumnWidth + state.activitiesRevealWidth) }
                content(topInset: state.rowHeight + 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state.sidebarVisible || state.sidebarPeeking {
                SidebarView(tabs: tabs, state: state, isOverlay: !state.sidebarVisible)
                    .frame(width: state.sidebarColumnWidth + state.activitiesRevealWidth)
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
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: state.activitiesDrawerOpen)
        .animation(.easeInOut(duration: 0.22), value: state.sidebarVisible)
        .animation(.easeInOut(duration: 0.22), value: state.sidebarPeeking)
    }

    private func content(topInset: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            if let tab = tabs.selectedTab {
                if let group = tabs.selectedSplit {
                    SplitContentView(tabs: tabs, state: state, group: group)
                } else {
                    TabContentView(tab: tab, state: state)
                }
            } else {
                NewTabView(state: state)
            }
            if state.findVisible {
                FindBarView(state: state).padding(.top, topInset).padding(.trailing, 14)
            }
            PasswordPromptOverlay().padding(.top, topInset)
        }
    }
}

private struct TabContentView: View {
    @ObservedObject var tab: BrowserTab
    let state: BrowserState

    var body: some View {
        if let failure = tab.navigationFailure {
            VStack(spacing: 8) {
                Text("Can’t open this page").font(.system(size: 20, weight: .semibold))
                Text(failure.message).foregroundStyle(.secondary)
                if let url = failure.url { Text(url.absoluteString).foregroundStyle(.secondary) }
                Button("Try Again") { tab.reload() }.padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tab.url != nil || tab.isLoading {
            WebViewHost(webView: tab.webView).id(tab.id)
                .overlay(alignment: .top) {
                    if tab.pullRefreshProgress > 0 {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(Double(tab.pullRefreshProgress) * 270))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .glass(in: Circle()).padding(.top, 8)
                            .opacity(Double(min(1, tab.pullRefreshProgress * 3)))
                            .accessibilityLabel(tab.pullRefreshProgress >= 1 ? "Release to reload" : "Pull to reload")
                            .allowsHitTesting(false)
                    }
                }
        } else {
            NewTabView(state: state)
        }
    }
}

/// 2 tabs sit side by side, 3 as three columns, 4 as a 2×2 grid.
private struct SplitContentView: View {
    @ObservedObject var tabs: TabManager
    let state: BrowserState
    let group: [BrowserTab]
    @State private var fraction: CGFloat = 0.5
    @State private var dragStart: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if group.count == 2 {
                GeometryReader { proxy in
                    let length = tabs.splitStacked ? proxy.size.height : proxy.size.width
                    let available = max(0, length - 8)
                    ZStack(alignment: .topLeading) {
                        // Stable identity keeps each WKWebView mounted while its position animates.
                        ForEach(group) { tab in
                            let first = group.first?.id == tab.id
                            let extent = available * (first ? fraction : 1 - fraction)
                            let offset = first ? 0 : available * fraction + 8
                            SplitPane(tab: tab, state: state, selected: tab.id == tabs.selectedID)
                                .frame(width: tabs.splitStacked ? proxy.size.width : extent,
                                       height: tabs.splitStacked ? extent : proxy.size.height)
                                .offset(x: tabs.splitStacked ? 0 : offset, y: tabs.splitStacked ? offset : 0)
                        }
                        splitDivider(length: available)
                            .frame(width: tabs.splitStacked ? proxy.size.width : 8,
                                   height: tabs.splitStacked ? 8 : proxy.size.height)
                            .offset(x: tabs.splitStacked ? 0 : available * fraction,
                                    y: tabs.splitStacked ? available * fraction : 0)
                    }
                }
            } else if group.count == 4 {
                VStack(spacing: 6) {
                    HStack(spacing: 6) { pane(0); pane(1) }
                    HStack(spacing: 6) { pane(2); pane(3) }
                }
            } else if tabs.splitStacked {
                VSplitView { ForEach(group.indices, id: \.self) { pane($0) } }
            } else {
                HSplitView { ForEach(group.indices, id: \.self) { pane($0) } }
            }
        }
        .padding(6)
        // Keep the window's own backdrop behind the panes so it never goes see-through.
        .background { SidebarBackground(tint: Pref.bool(Pref.tintKey, default: true) ? tabs.selectedTab?.themeColor.map { Color(nsColor: $0) } : nil, isOverlay: false).ignoresSafeArea() }
    }

    private func splitDivider(length: CGFloat) -> some View {
        Color.clear
            .frame(width: tabs.splitStacked ? nil : 8, height: tabs.splitStacked ? 8 : nil)
            .contentShape(Rectangle())
            .overlay {
                Capsule().fill(Color.secondary.opacity(0.35))
                    .frame(width: tabs.splitStacked ? 24 : 3, height: tabs.splitStacked ? 3 : 24)
                    .allowsHitTesting(false)
            }
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                    tabs.moveSplitPane(group[0], by: 1)
                }
            }
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                if dragStart == nil { dragStart = fraction }
                let delta = tabs.splitStacked ? value.translation.height : value.translation.width
                fraction = min(max((dragStart ?? 0.5) + delta / max(length, 1), 0.2), 0.8)
            }.onEnded { _ in dragStart = nil })
            .help("Drag to resize · Double-click to swap panes")
            .accessibilityLabel("Split divider")
            .accessibilityAction(named: "Swap panes") { tabs.moveSplitPane(group[0], by: 1) }
            .contextMenu {
                Button("Swap Panes") { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { tabs.moveSplitPane(group[0], by: 1) } }
                Button("Equal Sizes") { withAnimation(reduceMotion ? nil : .easeInOut) { fraction = 0.5 } }
                Button(tabs.splitStacked ? "Side by Side" : "Stack Vertically") { tabs.splitStacked.toggle() }
            }
    }

    private func pane(_ index: Int) -> some View {
        SplitPane(tab: group[index], state: state, selected: group[index].id == tabs.selectedID).id(group[index].id)
    }
}

private struct SplitPane: View {
    @ObservedObject var tab: BrowserTab
    let state: BrowserState
    let selected: Bool
    @State private var hovering = false
    @State private var pinned = false

    var body: some View {
        TabContentView(tab: tab, state: state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: hovering || pinned ? 8 : 0)
                    HStack(spacing: 8) {
                Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 24, height: 4)
                Button { state.tabs.selectTab(tab) } label: {
                    Text(tab.displayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help("Select pane")
                Menu {
                    Button("Focus This Tab", systemImage: "arrow.up.left.and.arrow.down.right") { state.tabs.focusOnly(tab) }
                    Button(state.tabs.splitStacked ? "Arrange Side by Side" : "Stack Vertically",
                           systemImage: "rectangle.split.2x1") { state.tabs.splitStacked.toggle() }
                        .disabled(state.tabs.splitIDs.count == 4)
                    Divider()
                    Button("Move Earlier", systemImage: "arrow.left") { state.tabs.moveSplitPane(tab, by: -1) }
                        .disabled(state.tabs.splitIDs.first == tab.id)
                    Button("Move Later", systemImage: "arrow.right") { state.tabs.moveSplitPane(tab, by: 1) }
                        .disabled(state.tabs.splitIDs.last == tab.id)
                    Button("Remove from Split", systemImage: "rectangle.badge.minus") { state.tabs.removeFromSplit(tab) }
                    Button("Move to New Window", systemImage: "macwindow") {
                        if let moved = state.tabs.detach(tab) { WindowCoordinator.shared.openWindow(adopting: moved) }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 22) }
                .menuStyle(.borderlessButton).fixedSize().help("Split pane options")
            }
                    .padding(.horizontal, 10).frame(height: 32)
                    .glass(in: Capsule(), interactive: true)
                    .frame(height: hovering || pinned ? 32 : 0)
                    .clipped()
                    .opacity(hovering || pinned ? 1 : 0)
                    .allowsHitTesting(hovering || pinned)
                    .accessibilityHidden(!hovering && !pinned)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, hovering || pinned ? 6 : 0)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.spring(response: 0.32, dampingFraction: 0.9), value: hovering)
            }
        .overlay(alignment: .top) {
            Color.clear.frame(height: 8).contentShape(Rectangle())
                .onHover { if $0 { hovering = true } }
                .allowsHitTesting(!hovering && !pinned)
        }
        .accessibilityAction(named: "Show pane controls") { pinned.toggle() }
        .frame(minWidth: 100, minHeight: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(selected ? 0.25 : 0.08), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
    }
}

/// While a tab is dragged over the page: a greyed, rounded box shows where the split will go,
/// and a page-preview card follows the pointer (like iPadOS split view).
private struct DragOverlay: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var tabs: TabManager

    var body: some View {
        if let drag = state.drag, drag.overContent, let tab = tabs.tabs.first(where: { $0.id == drag.tabID }) {
            ZStack {
                zone(count: tabs.selectedSplit?.count ?? 1, placeLeft: drag.placeLeft)
                DragGhost(tab: tab).position(drag.location)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.15), value: drag.placeLeft)
        }
    }

    private func zone(count: Int, placeLeft: Bool) -> some View {
        let c = state.contentRect
        let rect: CGRect
        switch count {
        case 1: rect = CGRect(x: placeLeft ? c.minX : c.midX, y: c.minY, width: c.width / 2, height: c.height)
        case 2: rect = CGRect(x: c.minX + c.width * 2 / 3, y: c.minY, width: c.width / 3, height: c.height)
        default: rect = CGRect(x: c.midX, y: c.midY, width: c.width / 2, height: c.height / 2)
        }
        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.clear).glass(in: RoundedRectangle(cornerRadius: 16), interactive: false)
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.gray.opacity(0.30)) }
            .overlay { Image(systemName: "rectangle.split.2x1").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary) }
            .padding(8)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: rect)
    }
}

private struct DragGhost: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image = tab.snapshot {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.primary.opacity(0.12).overlay { TabFavicon(tab: tab, size: 26) }
                }
            }
            .frame(width: 170, height: 104).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(tab.displayTitle).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(width: 170)
        }
        .padding(8)
        .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .scaleEffect(0.95)
    }
}

/// "Save password for …?" banner.
private struct PasswordPromptOverlay: View {
    @ObservedObject private var passwords = PasswordStore.shared

    var body: some View {
        if let pending = passwords.pending {
            HStack(spacing: 12) {
                Image(systemName: "key.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Save password for \(pending.host)?").font(.system(size: 12.5, weight: .semibold))
                    if !pending.username.isEmpty { Text(pending.username).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 12)
                Button("Never") { passwords.neverSave(pending.host) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Not Now") { passwords.pending = nil }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Save") { passwords.confirmPending() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 16).frame(height: 48).frame(maxWidth: 480)
            .glass(in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Live edge docks keep browser controls outside the page's interaction area.
private struct EngineDock: View {
    @ObservedObject var state: BrowserState
    let edge: String
    @AppStorage("aero.engine.address.dock") private var address = "sidebar"
    @AppStorage("aero.engine.navigation.dock") private var navigation = "sidebar"
    @AppStorage("aero.engine.activities.dock") private var activities = "sidebar"
    var body: some View {
        if address == edge || navigation == edge || activities == edge {
            HStack(spacing: 12) {
                if let tab = state.tabs.selectedTab {
                    if navigation == edge { NavigationPill(tab: tab, height: 34, iconSize: 13) }
                    if address == edge { OmniboxView(tab: tab, state: state, height: 34).frame(maxWidth: 640) }
                }
                if activities == edge { LiveActivitiesView(tabs: state.tabs).frame(width: 260) }
                Spacer(minLength: 0)
            }
            .padding(12).padding(.leading, edge == "top" ? 80 : 0)
            .glass(in: Rectangle(), interactive: false)
        }
    }
}

private struct EngineCanvas: View {
    @ObservedObject var state: BrowserState
    @AppStorage("aero.engine.address.dock") private var address = "sidebar"
    @AppStorage("aero.engine.navigation.dock") private var navigation = "sidebar"
    @AppStorage("aero.engine.activities.dock") private var activities = "sidebar"
    @State private var original: [String] = []
    @State private var selected = "address"
    private let components = [("address", "Address bar"), ("navigation", "Navigation"), ("activities", "Live Activities")]
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Make room for your way.").font(.title.weight(.semibold))
                            Text("Drag a component to an edge, or select it and click a destination.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Cancel") {
                            if original.count == 3 { address = original[0]; navigation = original[1]; activities = original[2] }
                            state.engineEditing = false
                            if Onboarding.needed { Onboarding.show() }
                        }
                        .keyboardShortcut(.cancelAction)
                        Button("Done") { state.engineEditing = false; if Onboarding.needed { Onboarding.show() } }.keyboardShortcut(.defaultAction)
                    }
                    HStack {
                        ForEach(components, id: \.0) { item in
                            Button(item.1) { selected = item.0 }
                                .padding(8).background(selected == item.0 ? Color.accentColor.opacity(0.2) : .clear, in: Capsule())
                                .onDrag { NSItemProvider(object: item.0 as NSString) }
                        }
                        Spacer()
                        Menu("Presets") {
                            Button("Classic") { address = "sidebar"; navigation = "sidebar"; activities = "sidebar" }
                            Button("Bottom address") { address = "bottom"; navigation = "top"; activities = "sidebar" }
                        }
                    }
                    zone("Top edge", "top").frame(height: 76)
                    HStack {
                        zone("Sidebar", "sidebar").frame(width: min(220, proxy.size.width * 0.25))
                        VStack(spacing: 12) {
                            Image(systemName: "globe").font(.system(size: 42)).foregroundStyle(.secondary)
                            Text("Space for the web").font(.title2)
                            Text("Controls dock at the edges so they never cover the page.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    zone("Bottom edge", "bottom").frame(height: 76)
                }
                .padding(24).glass(in: RoundedRectangle(cornerRadius: 24), interactive: false)
                .padding(24).padding(.top, 28)
            }
        }.onAppear { original = [address, navigation, activities] }
    }
    private func zone(_ title: String, _ dock: String) -> some View {
        Button { place(selected, at: dock) } label: {
            VStack(spacing: 8) {
                Text(title).font(.headline)
                Text(components.filter { location($0.0) == dock }.map(\.1).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [5])))
        }.buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first, components.contains(where: { $0.0 == item }) else { return false }
            place(item, at: dock); return true
        }
    }
    private func location(_ item: String) -> String { item == "address" ? address : item == "navigation" ? navigation : activities }
    private func place(_ item: String, at dock: String) {
        guard location(item) != dock else { return }
        if item == "address" { address = dock } else if item == "navigation" { navigation = dock } else { activities = dock }
        if UserDefaults.standard.object(forKey: "aero.haptics.enabled") as? Bool ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}


/// Horizontal chrome shares the real controls and tab model with the vertical layouts.
private struct HorizontalChrome: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var tabs: TabManager
    @ObservedObject var tab: BrowserTab
    @ObservedObject var favorites: FavoritesStore
    @State private var activitiesOpen = false
    @State private var downloadsOpen = false
    private var compact: Bool { state.layoutPreset == .compactHorizontal }
    private var tint: Color? {
        Pref.bool(Pref.tintKey, default: true) ? tab.themeColor.map { Color(nsColor: $0) } : nil
    }
    var body: some View {
        VStack(spacing: 6) {
            if !compact {
                HStack(spacing: 8) {
                    tabStrip
                    newTab
                }
                .padding(.leading, state.leadingInset)
                .padding(.trailing, 12)
                .frame(height: state.rowHeight)
            }
            HStack(spacing: 8) {
                ChromeToggleButton(iconSize: state.sidebarSize.iconSize + 1, help: "Show or Hide Sidebar (⌃⌘S)") {
                    state.toggleSidebar()
                }
                NavigationPill(tab: tab, height: 32, iconSize: state.sidebarSize.iconSize + 1)
                if compact { tabStrip.frame(minWidth: 60, maxWidth: .infinity) }
                OmniboxView(tab: tab, state: state, height: 34)
                    .frame(minWidth: compact ? 200 : 240, maxWidth: compact ? 420 : 680)
                    .layoutPriority(1)
                if !compact { Spacer(minLength: 0) }
                utilities
                ShareButton(url: tab.url, diameter: 30, iconSize: 16)
                if compact { newTab }
            }
            .padding(.leading, compact ? state.leadingInset : 12)
            .padding(.trailing, 12)
            .frame(height: compact ? state.rowHeight : 40)
        }
        .padding(.bottom, 8)
        .background { SidebarBackground(tint: tint, isOverlay: false) }
    }
    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(tabs.tabs) { item in
                        HorizontalTab(tab: item, tabs: tabs, compact: compact)
                            .id(item.id)
                    }
                }
            }.scrollIndicators(.hidden)
                .onAppear { if let id = tabs.selectedID { proxy.scrollTo(id) } }
                .onValueChange(of: tabs.selectedID) { id in if let id { proxy.scrollTo(id) } }
        }
    }
    private var newTab: some View {
        Button { state.newTab() } label: { Image(systemName: "plus").frame(width: 28, height: 30) }
            .buttonStyle(RubberButtonStyle()).help("New Tab (⌘T)").accessibilityLabel("New Tab")
    }
    private var utilities: some View {
        Menu {
            ForEach(favorites.items) { favorite in
                Button(favorite.title) { state.openFavorite(favorite) }
            }
            Divider()
            Button("Bookmarks") { state.bookmarksOpen = true }
            Button("Live Activities") { activitiesOpen = true }
            Button("Downloads") { downloadsOpen = true }
        } label: {
            Image(systemName: "ellipsis").frame(width: 28, height: 30)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Favorites, bookmarks and activities")
        .accessibilityLabel("Browser tools")
        .popover(isPresented: $state.bookmarksOpen) {
            BookmarksPanel(store: state.bookmarks, state: state, maxHeight: 440).frame(width: 320)
        }
        .popover(isPresented: $downloadsOpen) { DownloadsPopover(manager: .shared) }
        .popover(isPresented: $activitiesOpen) {
            HStack(spacing: 0) {
                ActivityToolDrawer(tabs: tabs) { activitiesOpen = false }.frame(width: 64)
                ScrollView { LiveActivitiesView(tabs: tabs).padding(12) }.frame(width: 300)
            }.frame(height: 400)
        }
    }
}

private struct HorizontalTab: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var tabs: TabManager
    let compact: Bool
    private var selected: Bool { tabs.selectedID == tab.id }
    var body: some View {
        HStack(spacing: 6) {
            Button { tabs.selectTab(tab) } label: {
                HStack(spacing: 6) {
                    TabFavicon(tab: tab, size: 16)
                    if !compact || selected { Text(tab.displayTitle).lineLimit(1).font(.system(size: 12, weight: .medium)) }
                    if let pane = tabs.splitIDs.firstIndex(of: tab.id) {
                        Text("\(pane + 1)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(RubberButtonStyle())
            if !compact || selected {
                Button { tabs.closeTab(tab) } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 20, height: 24) }
                    .buttonStyle(RubberButtonStyle()).help("Close Tab").accessibilityLabel("Close " + tab.displayTitle)
            }
        }
        .padding(.horizontal, 9).frame(width: compact ? (selected ? 140 : 34) : 180, height: 30)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(selected ? 0.14 : 0.04)))
        .help(tab.displayTitle)
        .modifier(TabHoverPreview(tab: tab))
        .contextMenu { TabContextMenu(tab: tab) }
    }
}
