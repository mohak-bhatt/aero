import SwiftUI

/// Ctrl+Tab switcher: hold Control to see live previews, tap Tab to move, release to switch.
struct TabSwitcherView: View {
    @ObservedObject var state: BrowserState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Array(state.switcherTabs.enumerated()), id: \.element.id) { index, tab in
                        SwitcherCard(tab: tab, selected: index == state.switcherIndex)
                            .id(tab.id)
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 860)
            .fixedSize(horizontal: true, vertical: true)
            .glass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            .onValueChange(of: state.switcherIndex) { index in
                if state.switcherTabs.indices.contains(index) { proxy.scrollTo(state.switcherTabs[index].id) }
            }
        }
    }
}

private struct SwitcherCard: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let snapshot = tab.snapshot {
                    Image(nsImage: snapshot).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.primary.opacity(0.08).overlay { TabFavicon(tab: tab, size: 28) }
                }
            }
            .frame(width: 170, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
            }
            HStack(spacing: 6) {
                TabFavicon(tab: tab, size: 14)
                Text(tab.displayTitle).font(.system(size: 11.5, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .frame(width: 170)
        }
        .opacity(selected ? 1 : 0.75)
        .scaleEffect(selected ? 1.04 : 1)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}
