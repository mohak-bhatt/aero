import SwiftUI

/// Horizontal layout, row 1: layout toggle, then one glass strip holding pinned icons and
/// equal-width tabs (drag to reorder, pull out for a new window) with + at the end.
struct TabStripView: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var manager: TabManager

    @State private var dragID: UUID?
    @State private var dragStart = 0
    @State private var dragTarget = 0
    @State private var dragX: CGFloat = 0
    @State private var dragOutside = false

    var body: some View {
        GeometryReader { geo in
            let list = manager.unpinnedTabs
            let pinned = manager.pinnedTabs
            let stripWidth = geo.size.width - state.leadingInset - 30 - 12 - 16
            let reserved = CGFloat(pinned.count) * 34 + 44
            let itemWidth = min(260, max(72, (stripWidth - reserved) / CGFloat(max(list.count, 1))))

            HStack(spacing: 10) {
                ChromeToggleButton(iconSize: state.sidebarSize.iconSize + 1, help: "Use Vertical Tabs (⌥⌘V)") {
                    state.toggleLayout()
                }

                HStack(spacing: 0) {
                    ForEach(pinned) { item in
                        PinnedTabTile(tab: item, cell: 30, isSelected: item.id == manager.selectedID,
                                      onSelect: { manager.selectTab(item) }, onUnpin: { manager.togglePin(item) },
                                      onFavorite: { state.toggleFavorite(item) }, onClose: { manager.closeTab(item) })
                    }
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        let dragged = dragID == item.id
                        let shift = tabShift(index: index, width: itemWidth)
                        HorizontalTab(tab: item, isSelected: item.id == manager.selectedID,
                                      onSelect: { manager.selectTab(item) }, onClose: { manager.closeTab(item) })
                            .frame(width: itemWidth)
                            .offset(x: dragged ? dragX : shift)
                            .scaleEffect(dragged ? (dragOutside ? 0.9 : 1.04) : 1)
                            .opacity(dragged && dragOutside ? 0.7 : 1)
                            .zIndex(dragged ? 10 : 0)
                            .animation(dragged ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: shift)
                            .animation(.easeOut(duration: 0.12), value: dragOutside)
                            .gesture(dragGesture(for: item, index: index, list: list, width: itemWidth))
                    }
                    ChromeIconButton(symbol: "plus", help: "New Tab (⌘T)", action: state.newTab)
                    Spacer(minLength: 0)
                }
                .padding(3)
                .frame(height: 36)
                .glass(in: Capsule())
            }
            .padding(.leading, state.leadingInset)
            .padding(.trailing, 12)
            .frame(height: state.rowHeight)
            .background(WindowDragArea())
        }
        .frame(height: state.rowHeight)
    }

    private func tabShift(index: Int, width: CGFloat) -> CGFloat {
        guard dragID != nil else { return 0 }
        if dragStart < dragTarget, index > dragStart, index <= dragTarget { return -width }
        if dragStart > dragTarget, index < dragStart, index >= dragTarget { return width }
        return 0
    }

    private func resetDrag() { dragID = nil; dragX = 0; dragTarget = 0; dragOutside = false }

    private func dragGesture(for tab: BrowserTab, index: Int, list: [BrowserTab], width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragID != tab.id { dragID = tab.id; dragStart = index; dragTarget = index }
                dragX = value.translation.width
                dragTarget = min(max(index + Int((value.translation.width / width).rounded()), 0), list.count - 1)
                let point = NSEvent.mouseLocation
                dragOutside = state.window.map { !$0.frame.insetBy(dx: -4, dy: -4).contains(point) } ?? false
            }
            .onEnded { value in
                let point = NSEvent.mouseLocation
                if dragOutside || abs(value.translation.height) > 90 {
                    resetDrag()
                    state.tearOff(tab, at: point)
                    return
                }
                let target = dragTarget, start = dragStart
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) { dragX = CGFloat(target - start) * width }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if target != start, list.indices.contains(target) { manager.move(tab, to: list[target]) }
                        resetDrag()
                    }
                }
            }
    }
}

private struct HorizontalTab: View {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            TabFavicon(tab: tab, size: 15)
            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(Capsule().fill(Color.primary.opacity(isSelected ? 0.16 : (hovering ? 0.08 : 0))))
        .contentShape(Capsule())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .contextMenu { TabContextMenu(tab: tab) }
    }
}
