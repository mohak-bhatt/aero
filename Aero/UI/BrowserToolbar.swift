import SwiftUI

/// Horizontal layout, row 2: same pieces as the sidebar, laid out like Safari but compact.
struct BrowserToolbar: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var state: BrowserState

    private var size: SidebarSize { state.sidebarSize }
    private var height: CGFloat { size.controlHeight - 6 }

    var body: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 8) {
                NavigationPill(tab: tab, height: height, iconSize: size.iconSize - 1)
                Spacer(minLength: 8)
                OmniboxView(tab: tab, state: state, height: height)
                    .frame(minWidth: 260, maxWidth: 620)
                    .zIndex(5)
                Spacer(minLength: 8)
                UpdateNowButton(compact: true)
                DownloadsButton(diameter: height, iconSize: size.iconSize + 1)
                ShareButton(url: tab.url, diameter: height, iconSize: size.iconSize - 1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height + 10)
        .overlay(alignment: .bottom) { LoadingBar(tab: tab) }
    }
}

private struct LoadingBar: View {
    @ObservedObject var tab: BrowserTab
    var body: some View {
        GeometryReader { proxy in
            Rectangle().fill(Color.accentColor)
                .frame(width: proxy.size.width * tab.progress, height: 2)
                .opacity(tab.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: tab.progress)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}
