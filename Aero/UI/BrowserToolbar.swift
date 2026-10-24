import SwiftUI

/// Horizontal layout, row 2 (like Safari): back/forward pill, centered address pill, and a
/// trailing pill with Downloads, Share and New Tab.
struct BrowserToolbar: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var state: BrowserState
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var downloadsOpen = false

    private let height: CGFloat = 36

    var body: some View {
        HStack(spacing: 10) {
            NavigationPill(tab: tab, height: height, iconSize: 14)
            Spacer(minLength: 8)
            OmniboxView(tab: tab, state: state, height: height)
                .frame(minWidth: 260, maxWidth: 640)
                .zIndex(5)
            Spacer(minLength: 8)
            UpdateNowButton(compact: true)
            trailingPill
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .overlay(alignment: .bottom) { LoadingBar(tab: tab) }
    }

    private var trailingPill: some View {
        HStack(spacing: 0) {
            pillButton("arrow.down.circle", "Downloads") { downloadsOpen.toggle() }
                .popover(isPresented: $downloadsOpen, arrowEdge: .bottom) { DownloadsPopover(manager: downloads) }
            if let url = tab.url, url.scheme?.hasPrefix("http") == true {
                ShareLink(item: url) { icon("square.and.arrow.up") }.buttonStyle(RubberButtonStyle()).help("Share")
            } else {
                icon("square.and.arrow.up").opacity(0.35)
            }
            pillButton("plus", "New Tab (⌘T)") { state.newTab() }
        }
        .glass(in: Capsule(), interactive: true)
    }

    private func pillButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(symbol) }.buttonStyle(RubberButtonStyle()).help(help)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 38, height: height)
            .contentShape(Rectangle())
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
