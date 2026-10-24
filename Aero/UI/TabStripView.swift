import SwiftUI

/// Horizontal layout, row 1 (title bar): layout toggle in the same spot as the sidebar toggle,
/// pinned icons, tabs (drag to reorder, pull out for a new window), new-tab button.
struct TabStripView: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var manager: TabManager

    @State private var dragID: UUID?
    @State private var dragStartIndex = 0
    @State private var dragTranslation: CGSize = .zero

    private let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let list = manager.unpinnedTabs
            let pinnedWidth = CGFloat(manager.pinnedTabs.count) * 32
            let available = geo.size.width - state.leadingInset - 30 - pinnedWidth - 56
            let count = CGFloat(max(list.count, 1))
            let itemWidth = min(210, max(44, (available - count * gap) / count))

            HStack(spacing: gap) {
                ChromeToggleButton(iconSize: state.sidebarSize.iconSize + 1, help: "Use Vertical Tabs (⌥⌘V)") {
                    state.toggleLayout()
                }
                .padding(.trailing, 6)

                ForEach(manager.pinnedTabs) { pinned in
                    PinnedTabTile(tab: pinned, cell: 28, isSelected: pinned.id == manager.selectedID,
                                  onSelect: { manager.selectTab(pinned) },
                                  onUnpin: { manager.togglePin(pinned) },
                                  onFavorite: { state.toggleFavorite(pinned) },
                                  onClose: { manager.closeTab(pinned) })
                }

                ForEach(list) { tab in
                    TabItemView(tab: tab, isSelected: tab.id == manager.selectedID,
                                onSelect: { manager.selectTab(tab) },
                                onClose: { manager.closeTab(tab) })
                        .frame(width: itemWidth)
                        .offset(x: dragOffset(for: tab, in: list, step: itemWidth + gap))
                        .zIndex(dragID == tab.id ? 1 : 0)
                        .gesture(dragGesture(for: tab, step: itemWidth + gap))
                }

                ChromeIconButton(symbol: "plus", help: "New Tab (⌘T)", action: state.newTab)
                Spacer(minLength: 0)
            }
            .padding(.leading, state.leadingInset)
            .padding(.trailing, 10)
            .frame(height: state.rowHeight)
            .background(WindowDragArea())
        }
        .frame(height: state.rowHeight)
    }

    private func dragOffset(for tab: BrowserTab, in list: [BrowserTab], step: CGFloat) -> CGFloat {
        guard dragID == tab.id, let current = list.firstIndex(where: { $0.id == tab.id }) else { return 0 }
        return dragTranslation.width - CGFloat(current - dragStartIndex) * step
    }

    private func dragGesture(for tab: BrowserTab, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let list = manager.unpinnedTabs
                if dragID != tab.id {
                    dragID = tab.id
                    dragStartIndex = list.firstIndex(where: { $0.id == tab.id }) ?? 0
                }
                dragTranslation = value.translation
                let target = min(max(dragStartIndex + Int((value.translation.width / step).rounded()), 0), list.count - 1)
                if let current = list.firstIndex(where: { $0.id == tab.id }), current != target {
                    withAnimation(.easeOut(duration: 0.15)) { manager.move(tab, to: list[target]) }
                }
            }
            .onEnded { value in
                let point = NSEvent.mouseLocation
                dragID = nil
                dragTranslation = .zero
                let outside = state.window.map { !$0.frame.insetBy(dx: -4, dy: -4).contains(point) } ?? false
                if outside || abs(value.translation.height) > 90 { state.tearOff(tab, at: point) }
            }
    }
}
