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
            SidebarContent(tabs: tabs, state: state, favorites: state.favorites, tab: tab, isOverlay: isOverlay)
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

    @State private var dragID: UUID?
    @State private var dragStartIndex = 0
    @State private var dragHeight: CGFloat = 0

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

            OmniboxView(tab: tab, state: state, height: size.pillHeight)
                .padding(.horizontal, size.hPad)
                .zIndex(5)

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
        .overlay(alignment: .trailing) { SidebarResizeHandle(state: state) }
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
            NavigationPill(tab: tab, height: controlHeight, iconSize: size.iconSize)
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

    // MARK: Tabs

    private var tabList: some View {
        let list = tabs.unpinnedTabs
        return VStack(spacing: 2) {
            ForEach(list) { item in
                SidebarTabRow(tab: item, size: size, isSelected: item.id == tabs.selectedID,
                              onSelect: { tabs.selectTab(item) },
                              onClose: { tabs.closeTab(item) },
                              onPin: { tabs.togglePin(item) },
                              onFavorite: { state.toggleFavorite(item) })
                    .offset(y: dragOffset(for: item, in: list))
                    .zIndex(dragID == item.id ? 1 : 0)
                    .gesture(dragGesture(for: item))
            }
        }
    }

    private func dragOffset(for item: BrowserTab, in list: [BrowserTab]) -> CGFloat {
        guard dragID == item.id, let current = list.firstIndex(where: { $0.id == item.id }) else { return 0 }
        return dragHeight - CGFloat(current - dragStartIndex) * rowStep
    }

    private func dragGesture(for item: BrowserTab) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let list = tabs.unpinnedTabs
                if dragID != item.id {
                    dragID = item.id
                    dragStartIndex = list.firstIndex(where: { $0.id == item.id }) ?? 0
                }
                dragHeight = value.translation.height
                let target = min(max(dragStartIndex + Int((value.translation.height / rowStep).rounded()), 0), list.count - 1)
                if let current = list.firstIndex(where: { $0.id == item.id }), current != target {
                    withAnimation(.easeOut(duration: 0.15)) { tabs.move(item, to: list[target]) }
                }
            }
            .onEnded { value in
                let point = NSEvent.mouseLocation
                dragID = nil
                dragHeight = 0
                let outside = state.window.map { !$0.frame.insetBy(dx: -4, dy: -4).contains(point) } ?? false
                if outside || value.translation.width > state.sidebarColumnWidth + 120 { state.tearOff(item, at: point) }
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

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blending: isOverlay ? .withinWindow : .behindWindow)
            if let tint { tint.opacity(0.55) }
        }
        .animation(.easeInOut(duration: 0.35), value: tint)
    }
}

// MARK: - Resizing

private struct SidebarResizeHandle: View {
    @ObservedObject var state: BrowserState
    @State private var startWidth: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? state.sidebarColumnWidth
                        startWidth = start
                        state.sidebarWidth = min(max(start + value.translation.width, state.sidebarSize.minWidth), 420)
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
                .glass(in: shape, tint: isCurrent ? Color.accentColor.opacity(0.35) : nil, interactive: true)
                .overlay { shape.strokeBorder(Color.primary.opacity(isCurrent ? 0.35 : 0), lineWidth: 1).allowsHitTesting(false) }
                .contentShape(shape)
        }
        .buttonStyle(RubberButtonStyle())
        .help(liveTab?.displayTitle ?? favorite.title)
        .contextMenu {
            if liveTab != nil { Button("Close Tab", action: onCloseTab) }
            Button("Remove from Favorites", action: onRemove)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let liveTab {
            TabFavicon(tab: liveTab, size: cell * 0.5)
        } else if let data = favorite.iconPNG, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().interpolation(.high)
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
            .contextMenu {
                Button("Unpin Tab", action: onUnpin)
                Button("Add to Favorites", action: onFavorite).disabled(tab.url == nil)
                Button("Close Tab", action: onClose)
            }
    }
}

private struct SidebarTabRow: View {
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
            Text(tab.displayTitle)
                .font(.system(size: size.font, weight: isSelected ? .medium : .regular))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .contextMenu {
            Button("Pin Tab", action: onPin)
            Button("Add to Favorites", action: onFavorite).disabled(tab.url == nil)
            Button("Close Tab", action: onClose)
        }
    }
}
