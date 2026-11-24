import SwiftUI
import AppKit

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Vertical-tabs sidebar. Window row (icon-only toggle + back/forward), address pill, favourite
/// tiles, pinned tabs, tab list with New Tab, then Downloads | Bookmarks pill | Share.
struct SidebarView: View {
    @ObservedObject var tabs: TabManager
    @ObservedObject var state: BrowserState
    var isOverlay = false

    var body: some View {
        if let tab = tabs.selectedTab {
            HStack(spacing: 0) {
                ActivityToolDrawer(tabs: tabs) { state.activitiesDrawerOpen = false }
                    .frame(width: 52)
                    .frame(width: state.activitiesRevealWidth, alignment: .leading)
                    .clipped().accessibilityHidden(state.activitiesRevealWidth == 0)
                Group {
                    if state.layoutPreset == .compact {
                        CompactSidebarContent(tabs: tabs, state: state, favorites: state.favorites, tab: tab, isOverlay: isOverlay)
                    } else {
                        SidebarContent(tabs: tabs, state: state, favorites: state.favorites, tab: tab, isOverlay: isOverlay)
                    }
                }.frame(width: state.sidebarColumnWidth)
            }
            .overlay(alignment: .trailing) { SidebarResizeHandle(state: state) }
            .background(SidebarSwipeSurface(width: state.activitiesRevealWidth) { width in
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { state.activitiesDragWidth = width }
            } settle: { open in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    state.activitiesDragWidth = nil
                    state.activitiesDrawerOpen = open
                }
            })
        } else {
            Color.clear
        }
    }
}

private struct SidebarContent: View {
    @ObservedObject var tabs: TabManager
    @ObservedObject var state: BrowserState
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var tab: BrowserTab
    let isOverlay: Bool
    @AppStorage("aero.engine.address.dock") private var addressDock = "sidebar"
    @AppStorage("aero.engine.navigation.dock") private var navigationDock = "sidebar"
    @AppStorage("aero.engine.activities.dock") private var activitiesDock = "sidebar"

    @State private var dragID: UUID?
    @State private var dragStartIndex = 0
    @State private var dragTarget = 0
    @State private var dragHeight: CGFloat = 0
    @State private var dragOutside = false

    private var size: SidebarSize { state.sidebarSize }
    private var controlHeight: CGFloat { size.controlHeight }
    private var tint: Color? {
        Pref.bool(Pref.tintKey, default: true) ? tab.themeColor.map { Color(nsColor: $0) } : nil
    }
    private var rowStep: CGFloat { size.rowHeight + 2 }
    private var topOverlap: CGFloat { max(0, (state.rowHeight - controlHeight) / 2 + size.spacing - 8) }

    var body: some View {
        VStack(spacing: size.spacing) {
            topRow.padding(.bottom, -topOverlap)

            if addressDock == "sidebar" {
                OmniboxView(tab: tab, state: state, height: size.pillHeight)
                    .padding(.horizontal, size.hPad).zIndex(5)
            }

            favoriteTiles

            ScrollView {
                VStack(spacing: size.spacing) {
                    pinnedRows
                    tabList
                    newTabButton
                }
                .padding(.horizontal, size.hPad)
                .padding(.top, 2)
            }
            .scrollIndicators(.hidden)

            bottomBar
        }
        .background { SidebarBackground(tint: tint, isOverlay: isOverlay).ignoresSafeArea() }
        .overlay { bookmarksDropdown }

        .contextMenu { BackgroundContextMenu() }
        .onValueChange(of: tabs.unpinnedTabs.count) { _ in resetDrag() }
    }

    // MARK: Window row

    private var topRow: some View {
        HStack(spacing: 8) {
            ChromeToggleButton(iconSize: size.iconSize + 1,
                               help: isOverlay ? "Keep Sidebar Open (⌃⌘S)" : "Hide Sidebar (⌃⌘S)") {
                state.sidebarVisible = isOverlay
                state.sidebarPeeking = false
            }
            Spacer(minLength: 0)
            if navigationDock == "sidebar" { NavigationPill(tab: tab, height: controlHeight, iconSize: size.iconSize + 1) }
        }
        .padding(.leading, state.leadingInset)
        .padding(.trailing, size.hPad)
        .frame(height: state.rowHeight)
        .background(WindowDragArea())
    }

    // MARK: Favourites and pinned (fixed-size tiles, centred like the iOS dock)

    @ViewBuilder
    private var favoriteTiles: some View {
        let items = favorites.items
        if !items.isEmpty {
            let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
            VStack(spacing: 10) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 10) {
                        ForEach(rows[index]) { favorite in
                            let live = tabs.favoriteTab(for: favorite)
                            FavoriteTile(favorite: favorite, liveTab: live, cell: size.favoriteCell,
                                         isCurrent: live != nil && live?.id == tabs.selectedID,
                                         onOpen: { state.openFavorite(favorite) },
                                         onCloseTab: { if let live { tabs.closeTab(live) } },
                                         onRemove: { state.removeFavorite(favorite) })
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, size.hPad)
        }
    }

    @ViewBuilder
    private var pinnedRows: some View {
        let pinned = tabs.pinnedTabs
        if !pinned.isEmpty {
            let rows = stride(from: 0, to: pinned.count, by: 5).map { Array(pinned[$0..<min($0 + 5, pinned.count)]) }
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        ForEach(rows[index]) { item in
                            PinnedTabTile(tab: item, cell: size.pinnedCell,
                                          isSelected: item.id == tabs.selectedID,
                                          onSelect: { tabs.selectTab(item) },
                                          onUnpin: { tabs.togglePin(item) },
                                          onFavorite: { state.toggleFavorite(item) },
                                          onClose: { tabs.closeTab(item) })
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Tabs (drag: reorder in place, over the page = split view, outside = new window)

    private var tabList: some View {
        let list = tabs.unpinnedTabs
        return VStack(spacing: 2) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                let dragged = dragID == item.id
                let shift = rowShift(index: index)
                SidebarTabRow(tab: item, size: size, isSelected: item.id == tabs.selectedID,
                              onSelect: { tabs.selectTab(item) },
                              onClose: { tabs.closeTab(item) },
                              onPin: { tabs.togglePin(item) },
                              onFavorite: { state.toggleFavorite(item) })
                    .modifier(TabHoverPreview(tab: item, showsSplitBadge: false))
                    .offset(y: dragged ? (dragOutside ? 0 : dragHeight) : shift)
                    .opacity(dragged && dragOutside ? 0.35 : 1)
                    .zIndex(dragged ? 10 : 0)
                    .animation(dragged ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: shift)
                    .animation(.easeOut(duration: 0.12), value: dragOutside)
                    .gesture(dragGesture(for: item, index: index, list: list))
            }
        }
    }

    private func rowShift(index: Int) -> CGFloat {
        guard dragID != nil, !dragOutside else { return 0 }
        if dragStartIndex < dragTarget, index > dragStartIndex, index <= dragTarget { return -rowStep }
        if dragStartIndex > dragTarget, index < dragStartIndex, index >= dragTarget { return rowStep }
        return 0
    }

    private func resetDrag() {
        dragID = nil; dragHeight = 0; dragTarget = 0; dragOutside = false
        state.drag = nil
    }

    private func dragGesture(for item: BrowserTab, index: Int, list: [BrowserTab]) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragID != item.id { dragID = item.id; dragStartIndex = index; dragTarget = index }
                dragHeight = value.translation.height
                state.dragMoved(item)
                dragOutside = state.drag?.overContent ?? false
                if !dragOutside {
                    dragTarget = min(max(index + Int((value.translation.height / rowStep).rounded()), 0), list.count - 1)
                }
            }
            .onEnded { _ in
                if state.dragEnded(item) { resetDrag(); return }
                let target = dragTarget, start = dragStartIndex
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    dragHeight = CGFloat(target - start) * rowStep      // settle into the slot
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if target != start, list.indices.contains(target) { tabs.move(item, to: list[target]) }
                        resetDrag()
                    }
                }
            }
    }

    private var newTabButton: some View {
        GlassButton(.capsule, help: "New Tab (⌘T)", width: controlHeight * 1.5, height: controlHeight * 0.85,
                    action: { state.newTab() }) {
            Image(systemName: "plus").font(.system(size: size.iconSize, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // MARK: Bottom: Downloads | Bookmarks pill | Share

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if activitiesDock == "sidebar" { LiveActivitiesView(tabs: tabs).padding(.horizontal, size.hPad) }
            UpdateNowButton().padding(.horizontal, size.hPad)
            bottomControls
        }
    }

    private var bottomControls: some View {
        GlassGroup(spacing: 12) {
            HStack {
                DownloadsButton(diameter: controlHeight, iconSize: size.iconSize + 3)
                Spacer(minLength: 0)
                GlassButton(.capsule, help: "Bookmarks (⌥⌘B)", width: controlHeight * 1.7, height: controlHeight,
                            action: { withAnimation(.easeOut(duration: 0.2)) { state.bookmarksOpen.toggle() } }) {
                    Image(systemName: state.bookmarksOpen ? "chevron.compact.down" : "chevron.compact.up")
                        .font(.system(size: size.iconSize + 4, weight: .semibold))
                }
                Spacer(minLength: 0)
                ShareButton(url: tab.url, diameter: controlHeight, iconSize: size.iconSize + 1)
            }
        }
        .padding(.horizontal, size.hPad)
        .padding(.bottom, 12)
    }

    /// Glass drop-down above the bottom bar, as wide as the address pill, never leaving the sidebar.
    private var bookmarksDropdown: some View {
        GeometryReader { geo in
            VStack {
                Spacer(minLength: 0)
                if state.bookmarksOpen {
                    BookmarksPanel(store: state.bookmarks, state: state,
                                   maxHeight: min(geo.size.height * 0.55, 440))
                        .frame(width: state.sidebarColumnWidth - 2 * size.hPad)
                        .padding(.bottom, controlHeight + 22)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Background (see-through; tinted only by non-white site colours)

struct SidebarBackground: View {
    let tint: Color?
    let isOverlay: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var matchedTint: Color? {
        guard let tint, let rgb = NSColor(tint).usingColorSpace(.sRGB) else { return nil }
        let lightness = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        if colorScheme == .dark && lightness > 0.78 { return nil }
        if colorScheme == .light && lightness < 0.16 { return nil }
        return tint
    }
    @AppStorage("aero.glass.intensity") private var intensity = 0.85
    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blending: isOverlay ? .withinWindow : .behindWindow)
                .opacity(isOverlay ? 1 : max(0.1, intensity))
            if let tint = matchedTint { tint.opacity(0.93) }
        }
        .animation(.easeInOut(duration: 0.35), value: tint)
    }
}

// MARK: - Resizing

private struct SidebarResizeHandle: View {
    @ObservedObject var state: BrowserState
    @State private var startWidth: CGFloat?
    @State private var beganCompact = false

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if startWidth == nil { startWidth = state.sidebarColumnWidth; beganCompact = state.layoutPreset == .compact }
                        let proposed = (startWidth ?? state.sidebarColumnWidth) + value.translation.width
                        let compact = beganCompact ? proposed < 84 : BrowserLayout.shouldCollapse(proposedWidth: proposed, minimumWidth: state.sidebarSize.minWidth)
                        if compact {
                            if state.layoutPreset != .compact { state.applyLayout(.compact); AeroHaptics.perform(.alignment) }
                        } else {
                            if state.layoutPreset == .compact { state.applyLayout(.classic); AeroHaptics.perform(.alignment) }
                            let expanded = beganCompact ? state.sidebarSize.minWidth + proposed - 84 : proposed
                            state.sidebarWidth = min(max(expanded, state.sidebarSize.minWidth), 420)
                        }
                    }
                    .onEnded { _ in startWidth = nil; state.persistSidebarWidth() })
            .modifier(ColumnResizeCursor())
    }
}

private struct ColumnResizeCursor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.columnResize)
        } else {
            content.onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
        }
    }
}

// MARK: - Tiles and rows

struct FavoriteTile: View {
    @EnvironmentObject private var state: BrowserState
    let favorite: Favorite
    let liveTab: BrowserTab?
    let cell: CGFloat
    let isCurrent: Bool
    let onOpen: () -> Void
    let onCloseTab: () -> Void
    let onRemove: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous) }

    var body: some View {
        Button(action: onOpen) {
            icon
                .frame(width: cell, height: cell)
                .glass(in: shape, tint: isCurrent ? Color.gray.opacity(0.24) : nil, interactive: true)
                .overlay { shape.strokeBorder(Color.primary.opacity(isCurrent ? 0.35 : 0), lineWidth: 1).allowsHitTesting(false) }
                .contentShape(shape)
        }
        .buttonStyle(RubberButtonStyle())
        .help(liveTab?.displayTitle ?? favorite.title)
        .modifier(TabHoverPreview(tab: liveTab, fallbackTitle: favorite.title, fallbackURL: favorite.url, previewsEnabled: false))
        .contextMenu {
            if let liveTab { TabContextMenu(tab: liveTab) }
            else {
                Button("Open Tab", action: onOpen)
                Button("Split with Current Tab") {
                    guard let anchor = state.tabs.selectedTab else { return }
                    let opened = state.tabs.newTab(url: favorite.url, select: false)
                    state.tabs.registerFavoriteTab(opened, for: favorite)
                    state.tabs.split(opened, with: anchor)
                }
                Button("Open in New Tab") { state.tabs.newTab(url: favorite.url) }
                Button("Copy Link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(favorite.url.absoluteString, forType: .string) }
                Button("Remove from Favorites", action: onRemove)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let liveTab, liveTab.favicon != nil || liveTab.isLoading {
            TabFavicon(tab: liveTab, size: cell * 0.5)
        } else if let data = favorite.iconPNG, let image = NSImage(data: data) {
            FaviconImage(image: image)
                .frame(width: cell * 0.5, height: cell * 0.5)
                .clipShape(RoundedRectangle(cornerRadius: cell * 0.11, style: .continuous))
        } else {
            Image(systemName: "globe").font(.system(size: cell * 0.4)).foregroundStyle(.secondary)
        }
    }
}

struct SelectedGlass<S: InsettableShape>: ViewModifier {
    let isSelected: Bool
    let shape: S
    func body(content: Content) -> some View {
        if isSelected { content.glass(in: shape) } else { content }
    }
}

/// Pinned tabs are plain icons: no resting backdrop, only a soft highlight when selected or hovered.
struct PinnedTabTile: View {
    @ObservedObject var tab: BrowserTab
    let cell: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onUnpin: () -> Void
    let onFavorite: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous) }

    var body: some View {
        TabFavicon(tab: tab, size: max(16, cell * 0.55))
            .frame(width: cell, height: cell)
            .background { if isSelected || hovering { shape.fill(Color.primary.opacity(isSelected ? 0.16 : 0.08)) } }
            .contentShape(shape)
            .onTapGesture(perform: onSelect)
            .onHover { hovering = $0 }
            .help(tab.displayTitle)
            .modifier(TabHoverPreview(tab: tab))
            .contextMenu { TabContextMenu(tab: tab) }
    }
}

struct SidebarTabRow: View {
    @EnvironmentObject private var state: BrowserState
    @ObservedObject var tab: BrowserTab
    let size: SidebarSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onPin: () -> Void
    let onFavorite: () -> Void

    @State private var hovering = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        HStack(spacing: 8) {
            TabFavicon(tab: tab, size: size.iconSize)
            if let pane = state.tabs.splitIDs.firstIndex(of: tab.id) {
                Text("\(pane + 1)").font(.system(size: 9, weight: .semibold, design: .rounded))
                    .frame(width: 16, height: 16)
                    .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    .help("Linked split · Pane \(pane + 1)")
                    .accessibilityLabel("Split pane \(pane + 1)")
            }
            Text(tab.displayTitle)
                .font(.system(size: size.font, weight: isSelected ? .medium : .regular))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            TabAudioBadge(tab: tab)
            if hovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(RubberButtonStyle())
                .help("Close Tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: size.rowHeight)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background { shape.fill(Color.primary.opacity(isSelected ? 0.14 : (hovering ? 0.08 : 0))) }
        .modifier(SelectedGlass(isSelected: isSelected, shape: shape))
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu { TabContextMenu(tab: tab) }
    }
}

/// Observe precise trackpad scrolling only inside this sidebar; leave vertical scrolling alone.
struct SidebarSwipeSurface: NSViewRepresentable {
    let width: CGFloat
    let change: (CGFloat) -> Void
    let settle: (Bool) -> Void
    func makeNSView(context: Context) -> SwipeView { let view = SwipeView(); configure(view); return view }
    func updateNSView(_ view: SwipeView, context: Context) { configure(view) }
    private func configure(_ view: SwipeView) { view.width = width; view.change = change; view.settle = settle }
    static func dismantleNSView(_ view: SwipeView, coordinator: ()) { view.stop() }
    final class SwipeView: NSView {
        var width: CGFloat = 0
        var change: ((CGFloat) -> Void)?
        var settle: ((Bool) -> Void)?
        private var monitor: Any?
        private var origin: CGFloat = 0
        private var distance: CGFloat = 0
        private var claimed = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, event.hasPreciseScrollingDeltas else { return event }
                guard self.claimed || self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                guard event.momentumPhase.isEmpty else { return event }
                if event.phase == .began { self.origin = self.width; self.distance = 0; self.claimed = false }
                if event.phase == .ended || event.phase == .cancelled {
                    guard self.claimed else { return event }
                    self.claimed = false
                    self.settle?(event.phase == .cancelled ? self.origin > 26 : self.width > 26)
                    return nil
                }
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || self.claimed else { return event }
                self.claimed = true
                self.distance += event.scrollingDeltaX
                let previous = self.width
                self.width = min(52, max(0, self.origin + self.distance))
                if (previous > 26) != (self.width > 26) { AeroHaptics.perform(.generic) }
                self.change?(self.width)
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}


/// Compact chrome keeps system window controls intact; detailed controls open at reading width.
private struct CompactSidebarContent: View {
    @ObservedObject var tabs: TabManager
    @ObservedObject var state: BrowserState
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var tab: BrowserTab
    let isOverlay: Bool
    @State private var addressOpen = false

    private var tint: Color? {
        Pref.bool(Pref.tintKey, default: true) ? tab.themeColor.map { Color(nsColor: $0) } : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            VerticalTrafficLights().frame(height: 84)
            ChromeToggleButton(iconSize: state.sidebarSize.iconSize + 1, help: "Hide Sidebar (⌃⌘S)") {
                state.toggleSidebar()
            }.frame(height: 30)
            NavigationPill(tab: tab, height: 28, iconSize: 15, vertical: true)
            Button { addressOpen = true; state.pendingOmniboxFocus = true } label: {
                Image(systemName: "magnifyingglass").frame(width: 32, height: 30)
            }
            .buttonStyle(.borderless).help("Search or enter website (⌘L)")
            .accessibilityLabel("Address and page options")
            .popover(isPresented: $addressOpen, arrowEdge: .trailing) {
                VStack(spacing: 6) {
                    OmniboxView(tab: tab, state: state, height: 36)
                    if !state.suggestions.isEmpty { SuggestionsView(state: state) }
                }.padding(12).frame(width: 360)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(favorites.items) { favorite in
                        let live = tabs.favoriteTab(for: favorite)
                        FavoriteTile(favorite: favorite, liveTab: live, cell: 32,
                            isCurrent: live?.id == tabs.selectedID,
                            onOpen: { state.openFavorite(favorite) },
                            onCloseTab: { if let live { tabs.closeTab(live) } },
                            onRemove: { state.removeFavorite(favorite) })
                    }
                    if !favorites.items.isEmpty { Divider().padding(.horizontal, 12) }
                    ForEach(tabs.pinnedTabs + tabs.unpinnedTabs) { item in
                        PinnedTabTile(tab: item, cell: 32, isSelected: item.id == tabs.selectedID,
                            onSelect: { tabs.selectTab(item) }, onUnpin: { tabs.togglePin(item) },
                            onFavorite: { state.toggleFavorite(item) }, onClose: { tabs.closeTab(item) })
                            .accessibilityLabel(item.displayTitle)
                    }
                    Button { state.newTab() } label: {
                        Image(systemName: "plus").frame(width: 32, height: 30)
                    }.buttonStyle(.borderless).help("New Tab (⌘T)")
                }.frame(maxWidth: .infinity)
            }.scrollIndicators(.hidden)
            CompactLiveActivities(tabs: tabs)
            DownloadsButton(diameter: 30, iconSize: 15)
            Button { state.bookmarksOpen.toggle() } label: {
                Image(systemName: "chevron.compact.right").font(.system(size: 20, weight: .medium))
                    .frame(width: 28, height: 40)
                    .glass(in: Capsule(), interactive: true)
            }.buttonStyle(.borderless).help("Bookmarks (⌥⌘B)")
                .accessibilityLabel("Bookmarks")
                .popover(isPresented: $state.bookmarksOpen, arrowEdge: .trailing) {
                    BookmarksPanel(store: state.bookmarks, state: state, maxHeight: 440).frame(width: 320)
                }
            ShareButton(url: tab.url, diameter: 30, iconSize: 15)
        }
        .padding(.bottom, 12)
        .background { SidebarBackground(tint: tint, isOverlay: isOverlay).ignoresSafeArea() }
        .contextMenu {
            Button("Expand Sidebar") { state.applyLayout(.classic) }
            Button("Activity Tools") { state.activitiesDrawerOpen.toggle() }
            BackgroundContextMenu()
        }
        .onAppear { if state.pendingOmniboxFocus { addressOpen = true } }
        .onValueChange(of: state.pendingOmniboxFocus) { if $0 { addressOpen = true } }
        .onValueChange(of: tab.url) { _ in addressOpen = false }
    }
}
