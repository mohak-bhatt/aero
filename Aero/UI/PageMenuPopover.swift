import SwiftUI

/// Safari-style page menu: Zoom stepper, Find on Page, Website Settings, plus tab actions.
struct PageMenuPopover: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var state: BrowserState
    @ObservedObject var manager: TabManager
    let dismiss: () -> Void

    @State private var showingSettings = false
    @State private var clearedMessage: String?

    private var isFavorite: Bool { manager.favoriteID(of: tab) != nil }
    private var zoomPercent: Int { Int((tab.zoom * 100).rounded()) }

    var body: some View {
        VStack(spacing: 2) {
            if showingSettings { settings } else { main }
        }
        .padding(6)
        .font(.system(size: 12.5))
        .frame(width: 232)
    }

    private var main: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "plus.magnifyingglass").frame(width: 16)
                Text("Zoom")
                Spacer()
                Text("\(zoomPercent)%").monospacedDigit().foregroundStyle(.secondary)
                Stepper("", onIncrement: { tab.zoomIn() }, onDecrement: { tab.zoomOut() })
                    .labelsHidden()
            }
            .padding(.horizontal, 10)
            .frame(height: 28)

            PageMenuDivider()
            PageMenuRow(icon: "doc.text.magnifyingglass", title: "Find on Page…") {
                dismiss(); state.showFind()
            }
            PageMenuRow(icon: "gearshape", title: "Website Settings…") { showingSettings = true }

            PageMenuDivider()
            PageMenuRow(icon: "link", title: "Copy Link", disabled: tab.url == nil) {
                if let url = tab.url {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                dismiss()
            }
            PageMenuRow(icon: manager.isPinned(tab) ? "pin.slash" : "pin",
                        title: manager.isPinned(tab) ? "Unpin Tab" : "Pin Tab",
                        disabled: isFavorite) {
                manager.togglePin(tab); dismiss()
            }
            PageMenuRow(icon: isFavorite ? "star.slash" : "star",
                        title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                        disabled: tab.url == nil) {
                state.toggleFavorite(tab); dismiss()
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Button { showingSettings = false; clearedMessage = nil } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(tab.url?.host ?? "Website").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)

            PageMenuDivider()
            PageMenuRow(icon: "textformat.size", title: "Reset Zoom (\(zoomPercent)%)") { tab.resetZoom() }
            PageMenuRow(icon: "trash", title: "Clear Data for This Website", disabled: tab.url?.host == nil) {
                guard let host = tab.url?.host else { return }
                Task {
                    await state.clearWebsiteData(host: host)
                    clearedMessage = "Cookies and site data cleared."
                }
            }
            if let clearedMessage {
                Text(clearedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
    }
}

private struct PageMenuDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5).padding(.vertical, 4).padding(.horizontal, 6)
    }
}

private struct PageMenuRow: View {
    let icon: String
    let title: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(hovering && !disabled ? 0.1 : 0)))
        .onHover { hovering = $0 }
    }
}
