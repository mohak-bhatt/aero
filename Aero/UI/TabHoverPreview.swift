import SwiftUI

/// The same interactive preview serves ordinary, pinned and favourite tabs.
struct TabHoverPreview: ViewModifier {
    @EnvironmentObject var state: BrowserState
    let tab: BrowserTab?
    var fallbackTitle = ""
    var fallbackURL: URL? = nil
    var showsSplitBadge = true
    @State private var open = false
    @State private var pending: DispatchWorkItem?
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) { if showsSplitBadge, let tab { TabAudioBadge(tab: tab) } }
            .overlay(alignment: .bottomTrailing) {
                if showsSplitBadge, let tab, let index = state.tabs.splitIDs.firstIndex(of: tab.id) {
                    Text("\(index + 1)").font(.system(size: 8, weight: .bold))
                        .padding(3).background(.regularMaterial, in: Circle())
                        .help("Split pane \(index + 1)").allowsHitTesting(false)
                }
            }
            .onHover { inside in schedule(inside, delay: inside ? 0.45 : 0.35) }
            .popover(isPresented: $open, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tab?.displayTitle ?? fallbackTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        Spacer(minLength: 8)
                        if let tab {
                            Button { open = false; state.tabs.closeTab(tab) } label: {
                                Image(systemName: "xmark").frame(width: 24, height: 24)
                            }.buttonStyle(.borderless).help("Close Tab").accessibilityLabel("Close " + tab.displayTitle)
                        }
                    }
                    Group {
                        if let snapshot = tab?.snapshot { Image(nsImage: snapshot).resizable().scaledToFill() }
                        else { Color.primary.opacity(0.06).overlay { Image(systemName: "globe").font(.title) } }
                    }.frame(width: 224, height: 126).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                    Text((tab?.url ?? fallbackURL)?.host ?? "New Tab").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.padding(12).frame(width: 248)
                    .onHover { inside in schedule(inside, delay: inside ? 0 : 0.35) }
            }
            .onDisappear { pending?.cancel(); open = false }
    }
    private func schedule(_ inside: Bool, delay: Double) {
        pending?.cancel()
        let work = DispatchWorkItem { if state.drag == nil { open = inside } else { open = false } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// Blue vector glyph stays sharp at every display scale; muting does not navigate the tab.
struct TabAudioBadge: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var hub = MediaHub.shared
    var body: some View {
        if hub.items[tab.id]?.isPlaying == true || tab.audioMuted {
            Button { tab.toggleTabAudio() } label: {
                Image(systemName: tab.audioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.blue)
                    .frame(width: 18, height: 18).background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain).help(tab.audioMuted ? "Unmute Tab" : "Mute Tab")
                .accessibilityLabel(tab.audioMuted ? "Unmute Tab" : "Mute Tab")
        }
    }
}

// Kept as a compatibility slot for the window overlay; previews now own their hit testing.
struct HoverPreviewOverlay: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var tabs: TabManager
    var body: some View { EmptyView() }
}
