import SwiftUI
import AppKit

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct BookmarkIcon: View {
    let node: BookmarkNode
    var size: CGFloat = 15

    var body: some View {
        if node.isFolder {
            Image(systemName: "folder").font(.system(size: size)).foregroundStyle(.secondary)
        } else if let data = node.iconPNG, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: "globe").font(.system(size: size)).foregroundStyle(.secondary)
        }
    }
}

/// Shared right-click / context menu for a bookmark or folder.
private struct BookmarkContextMenu: View {
    let node: BookmarkNode
    @ObservedObject var store: BookmarkStore
    let state: BrowserState

    var body: some View {
        if node.isFolder {
            Button("Open All in Tabs") { state.openAll(in: node) }
            Button("New Folder") { state.newBookmarkFolder(in: node.id) }
            Button("Add Bookmark Here…") { state.addBookmarkForCurrentTab(in: node.id) }
        } else {
            Button("Open") { state.openBookmark(node, inNewTab: false) }
            Button("Open in New Tab") { state.openBookmark(node, inNewTab: true) }
            Button("Copy Link") {
                if let url = node.url {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
        Divider()
        Button("Rename…") {
            if let name = Prompt.text(title: "Rename", initial: node.title, button: "Rename"), !name.isEmpty {
                store.rename(node.id, to: name)
            }
        }
        Menu("Move To") {
            Button("Bookmarks (top level)") { store.move(node.id, to: nil) }
            ForEach(store.folderList(), id: \.id) { folder in
                Button(String(repeating: "   ", count: folder.depth) + folder.title) { store.move(node.id, to: folder.id) }
                    .disabled(folder.id == node.id)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { store.delete(node.id) }
    }
}

/// Liquid Glass drop-down listing bookmarks as a Finder-like tree.
struct BookmarksPanel: View {
    @ObservedObject var store: BookmarkStore
    let state: BrowserState
    let maxHeight: CGFloat

    @State private var expanded: Set<UUID> = []
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Bookmarks").font(.system(size: 12, weight: .semibold))
                Spacer()
                headerButton("plus", "Add Bookmark for This Page (⌘D)") { state.addBookmarkForCurrentTab() }
                headerButton("folder.badge.plus", "New Folder") { state.newBookmarkFolder() }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.items.isEmpty {
                        Text("No bookmarks yet. Press ＋ to add this page.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(14)
                    } else {
                        BookmarkRows(nodes: store.items, depth: 0, store: store, state: state, expanded: $expanded)
                    }
                }
                .padding(6)
                .background(GeometryReader { Color.clear.preference(key: PanelHeightKey.self, value: $0.size.height) })
            }
            .scrollIndicators(.hidden)
            .frame(height: min(rowsHeight, maxHeight - 36))
            .animation(.easeOut(duration: 0.18), value: rowsHeight)
        }
        .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    /// Height follows exactly what is visible: every row plus every expanded folder.
    private var rowsHeight: CGFloat { store.items.isEmpty ? 56 : visibleRows(store.items) + 12 }

    private func visibleRows(_ nodes: [BookmarkNode]) -> CGFloat {
        nodes.reduce(0) { total, node in
            var next = total + 28
            if node.isFolder, expanded.contains(node.id) {
                let kids = node.children ?? []
                next += kids.isEmpty ? 22 : visibleRows(kids)
            }
            return next
        }
    }

    private func headerButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }
}

private struct BookmarkRows: View {
    let nodes: [BookmarkNode]
    let depth: Int
    @ObservedObject var store: BookmarkStore
    let state: BrowserState
    @Binding var expanded: Set<UUID>

    var body: some View {
        ForEach(nodes) { node in
            BookmarkRow(node: node, depth: depth, isOpen: expanded.contains(node.id), store: store, state: state) {
                if node.isFolder {
                    if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
                } else {
                    state.openBookmark(node, inNewTab: false)
                }
            }
            if node.isFolder, expanded.contains(node.id) {
                if (node.children ?? []).isEmpty {
                    Text("Empty").font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.leading, CGFloat(depth + 1) * 14 + 30).frame(height: 22)
                } else {
                    AnyView(BookmarkRows(nodes: node.children ?? [], depth: depth + 1, store: store, state: state, expanded: $expanded))
                }
            }
        }
    }
}

private struct BookmarkRow: View {
    let node: BookmarkNode
    let depth: Int
    let isOpen: Bool
    @ObservedObject var store: BookmarkStore
    let state: BrowserState
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if node.isFolder {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            BookmarkIcon(node: node)
            Text(node.title).font(.system(size: 12.5)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14 + 6)
        .padding(.trailing, 6)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .contextMenu { BookmarkContextMenu(node: node, store: store, state: state) }
    }
}

/// Folder-aware menu items, shared by the bookmarks bar and the Bookmarks menu.
struct BookmarkMenuItems: View {
    let nodes: [BookmarkNode]
    let open: (BookmarkNode) -> Void

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                Menu(node.title) { AnyView(BookmarkMenuItems(nodes: node.children ?? [], open: open)) }
            } else {
                Button(node.title) { open(node) }
            }
        }
    }
}

/// Horizontal layout, row 3: favourites then bookmarks, compact like a classic bookmarks bar.
struct BookmarksBar: View {
    let state: BrowserState
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var store: BookmarkStore
    @ObservedObject var tabs: TabManager

    var body: some View {
        if !favorites.items.isEmpty || !store.items.isEmpty {
            GeometryReader { geo in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(favorites.items) { favorite in
                        let live = tabs.favoriteTab(for: favorite)
                        FavoriteTile(favorite: favorite, liveTab: live, cell: 26,
                                     isCurrent: live != nil && live?.id == tabs.selectedID,
                                     onOpen: { state.openFavorite(favorite) },
                                     onCloseTab: { if let live { tabs.closeTab(live) } },
                                     onRemove: { state.removeFavorite(favorite) })
                    }
                    if !favorites.items.isEmpty && !store.items.isEmpty {
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 0.5, height: 16).padding(.horizontal, 4)
                    }
                    ForEach(store.items) { node in
                        BarItem(node: node, store: store, state: state)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minWidth: geo.size.width)
            }
            .scrollIndicators(.hidden)
            }
            .frame(height: 32)
        }
    }
}

private struct BarItem: View {
    let node: BookmarkNode
    @ObservedObject var store: BookmarkStore
    let state: BrowserState
    @State private var hovering = false

    var body: some View {
        Group {
            if node.isFolder {
                Menu {
                    BookmarkMenuItems(nodes: node.children ?? []) { state.openBookmark($0, inNewTab: false) }
                } label: { label }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            } else {
                Button { state.openBookmark(node, inNewTab: false) } label: { label }.buttonStyle(.plain)
            }
        }
        .contextMenu { BookmarkContextMenu(node: node, store: store, state: state) }
    }

    private var label: some View {
        HStack(spacing: 5) {
            BookmarkIcon(node: node, size: 13)
            Text(node.title).font(.system(size: 12)).lineLimit(1)
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        .onHover { hovering = $0 }
    }
}
