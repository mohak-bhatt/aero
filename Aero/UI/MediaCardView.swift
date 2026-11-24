import SwiftUI
import CoreImage

/// The media presentation used by the sidebar's single Live Activities component.
struct MediaCardView: View {
    @ObservedObject private var hub = MediaHub.shared
    @ObservedObject var tabs: TabManager
    var onlyTabID: UUID? = nil

    var body: some View {
        ForEach(sources, id: \.tab.id) { source in
            Group {
                if source.info.isVideo && source.info.isMainFrame {
                    LiveVideoCard(tab: source.tab, info: source.info) { tabs.selectTab(source.tab) }
                } else {
                    AudioCard(tab: source.tab, info: source.info) { tabs.selectTab(source.tab) }
                }
            }
            .contextMenu {
                Button("Dismiss Live Activity") { hub.dismiss(source.tab.id) }
                Button("Go to Playing Tab") { tabs.selectTab(source.tab) }
            }
            .id(source.tab.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var sources: [(tab: BrowserTab, info: MediaInfo)] {
        hub.order.compactMap { id in
            guard (onlyTabID == nil || onlyTabID == id), id != tabs.selectedID, !(tabs.selectedSplit?.contains { $0.id == id } ?? false),
                  let tab = tabs.tabs.first(where: { $0.id == id }), let info = hub.items[id],
                  hub.permits(id, url: tab.url) else { return nil }
            return (tab, info)
        }
    }
}

/// Five explicit actions; secondary controls never take space from the transport row.
private struct MediaTransport: View {
    let tab: BrowserTab
    let info: MediaInfo
    var body: some View {
        HStack(spacing: 0) {
            control("backward.end.fill", "Previous track", "prev")
            Spacer(minLength: 0)
            if info.isVideo {
                control("gobackward.10", "Back 10 seconds", "back10").disabled(info.duration <= 0)
                Spacer(minLength: 0)
            }
            control(info.isPlaying ? "pause.fill" : "play.fill", info.isPlaying ? "Pause" : "Play", "toggle", size: 21)
            Spacer(minLength: 0)
            if info.isVideo {
                control("goforward.10", "Forward 10 seconds", "fwd10").disabled(info.duration <= 0)
                Spacer(minLength: 0)
            }
            control("forward.end.fill", "Next track", "next")
        }
    }
    private func control(_ symbol: String, _ label: String, _ command: String, size: CGFloat = 14) -> some View {
        Button { tab.mediaCommand(command) } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 32).contentShape(Rectangle())
        }.buttonStyle(RubberButtonStyle()).help(label).accessibilityLabel(label)
    }
}

private struct LiveVideoCard: View {
    @ObservedObject var tab: BrowserTab
    let info: MediaInfo
    let goToTab: () -> Void
    @State private var hovering = false
    @State private var pinned = false
    @State private var width: CGFloat = 240
    @FocusState private var keyboardFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var revealed: Bool { hovering || pinned || keyboardFocus }
    private var videoHeight: CGFloat { min(width / info.videoAspectRatio, 360) }

    var body: some View {
        VStack(spacing: revealed ? 6 : 0) {
            GeometryReader { proxy in
                WebViewHost(webView: tab.webView)
                    .frame(width: min(proxy.size.width, 360 * info.videoAspectRatio), height: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        Button { pinned.toggle() } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(RubberButtonStyle()).focused($keyboardFocus)
                            .accessibilityLabel(pinned ? "Hide video controls" : "Show video controls")
                            .help("Hover to reveal controls. Click to keep them open.")
                    }
                    .overlay(alignment: .topTrailing) {
                        if revealed {
                            HStack(spacing: 2) {
                                overlayButton("speaker.wave.2", "Mute or unmute") { tab.mediaCommand("mute") }
                                overlayButton("pip.enter", "Picture in Picture") { tab.mediaCommand("pip") }
                                overlayButton("arrow.up.right", "Go to playing tab", action: goToTab)
                            }
                            .padding(3).glass(in: Capsule(), interactive: true).padding(6)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear { width = proxy.size.width }
                    .onValueChange(of: proxy.size.width) { width = $0 }
            }.frame(height: videoHeight)

            if revealed {
                VStack(spacing: 5) {
                    MediaTransport(tab: tab, info: info)
                    if info.duration > 0 { MediaTimeline(tab: tab, info: info) }
                    else { Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                }
                .padding(10)
                .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: revealed)
        .onAppear { tab.mediaCommand("lift") }
        .onDisappear { tab.mediaCommand("unlift") }
    }
    private func overlayButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24)
        }.buttonStyle(RubberButtonStyle()).help(label).accessibilityLabel(label)
    }
}

/// Native Now Playing proportions, with transport kept beside the artwork.
private struct AudioCard: View {
    @ObservedObject var tab: BrowserTab
    let info: MediaInfo
    let goToTab: () -> Void
    @State private var hovering = false
    @State private var pinned = false
    @State private var artworkExpanded = false
    @State private var artworkTint: Color = .blue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var expanded: Bool { hovering || pinned || artworkExpanded }

    var body: some View {
        VStack(spacing: 12) {
            if artworkExpanded {
                artworkButton
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
            HStack(spacing: 10) {
                if !artworkExpanded {
                    artworkButton.frame(width: 52, height: 52)
                }
                Button(action: goToTab) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(expanded ? 2 : 1).truncationMode(.tail)
                        .help(info.title)
                    Text(info.artist).font(.system(size: 11))
                        .foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(RubberButtonStyle()).help("Go to playing tab")
                    .accessibilityLabel("Go to playing tab: " + info.title)
                PlaybackIndicator(isPlaying: info.isPlaying, tint: artworkTint)
            }
            if expanded {
                if info.duration > 0 { MediaTimeline(tab: tab, info: info).tint(artworkTint) }
                HStack(spacing: 0) {
                    Button(action: goToTab) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 12, weight: .medium))
                            .frame(width: 24, height: 28)
                    }.buttonStyle(RubberButtonStyle()).foregroundStyle(.secondary)
                        .help("Go to playing tab").accessibilityLabel("Go to playing tab")
                    Spacer(minLength: 4)
                    transport("backward.fill", "Previous track", "prev", size: 15)
                    Spacer(minLength: 6)
                    transport(info.isPlaying ? "pause.fill" : "play.fill",
                              info.isPlaying ? "Pause" : "Play", info.isPlaying ? "pause" : "play", size: 23)
                    Spacer(minLength: 6)
                    transport("forward.fill", "Next track", "next", size: 15)
                    Spacer(minLength: 4)
                    Menu { playerOptions } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                            .frame(width: 24, height: 28)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("More playback options").accessibilityLabel("More playback options")
                }
            }
        }
        .padding(12)
        .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottom) {
            if !expanded && info.duration > 0 {
                GeometryReader { proxy in
                    Capsule().fill(artworkTint.opacity(0.16))
                        .overlay(alignment: .leading) {
                            Capsule().fill(artworkTint)
                                .frame(width: proxy.size.width * min(1, max(0, info.currentTime / info.duration)))
                        }
                }
                .frame(height: 2).padding(.horizontal, 14).padding(.bottom, 5)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expanded)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: artworkExpanded)
        .contextMenu { playerOptions }
        .task(id: info.artworkURL) {
            artworkTint = .blue
            guard let url = info.artworkURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled, data.count < 10_000_000,
                  let image = CIImage(data: data), !image.extent.isEmpty,
                  let average = image.applyingFilter("CIAreaAverage", parameters: ["inputExtent": CIVector(cgRect: image.extent)]) as CIImage? else { return }
            var pixel = [UInt8](repeating: 0, count: 4)
            CIContext().render(average, toBitmap: &pixel, rowBytes: 4,
                               bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            let color = NSColor(srgbRed: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255,
                                blue: Double(pixel[2]) / 255, alpha: 1)
            // Lift dark covers so the small indicators stay legible on glass.
            artworkTint = Color(nsColor: NSColor(calibratedHue: color.hueComponent,
                saturation: min(0.8, max(0.25, color.saturationComponent)),
                brightness: max(0.72, color.brightnessComponent), alpha: 1))
        }
    }
    private var artworkButton: some View {
        Button { artworkExpanded.toggle() } label: { artwork }
            .buttonStyle(RubberButtonStyle())
            .help(artworkExpanded ? "Shrink album artwork" : "Expand album artwork")
            .accessibilityLabel(artworkExpanded ? "Shrink album artwork" : "Expand album artwork")
    }
    @ViewBuilder private var playerOptions: some View {
        Button("Go to Playing Tab", systemImage: "arrow.up.right.square", action: goToTab)
        Button("Mute or Unmute", systemImage: "speaker.wave.2") { tab.mediaCommand("mute") }
        Toggle("Expand Album Artwork", isOn: $artworkExpanded)
        Toggle("Keep Controls Open", isOn: $pinned)
        Divider()
        Button("Dismiss Live Activity", systemImage: "xmark.circle") { MediaHub.shared.dismiss(tab.id) }
    }
    private func transport(_ symbol: String, _ label: String, _ command: String, size: CGFloat) -> some View {
        Button { tab.mediaCommand(command) } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .frame(width: 26, height: 28).contentShape(Rectangle())
        }.buttonStyle(RubberButtonStyle()).help(label).accessibilityLabel(label)
    }
    private var artwork: some View {
        GeometryReader { proxy in
            Group {
                if let url = info.artworkURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { placeholder }
                } else { placeholder }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    private var placeholder: some View {
        Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Decorative playback state indicator; does not capture or analyse website audio.
struct PlaybackIndicator: View {
    let isPlaying: Bool
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isPlaying || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4) { index in
                    let level = isPlaying && !reduceMotion
                        ? 4 + 12 * (0.5 + 0.5 * sin(time * (4 + Double(index) * 0.6) + Double(index) * 1.7))
                        : (isPlaying ? Double(7 + index * 2) : 3)
                    Capsule().fill(isPlaying ? tint : Color.secondary.opacity(0.5))
                        .frame(width: 2, height: level)
                }
            }.frame(width: 14, height: 18)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

private struct MediaTimeline: View {
    let tab: BrowserTab
    let info: MediaInfo
    @State private var seeking = false
    @State private var position: Double = 0
    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { seeking ? position : min(info.currentTime, info.duration) },
                                  set: { position = $0 }), in: 0...max(1, info.duration), onEditingChanged: { editing in
                if editing { position = min(info.currentTime, info.duration) }
                seeking = editing
                if !editing { tab.seekMedia(to: position) }
            }).controlSize(.mini).accessibilityLabel("Playback position")
            HStack {
                Text(time(seeking ? position : info.currentTime))
                Spacer()
                Text("−" + time(max(0, info.duration - (seeking ? position : info.currentTime))))
            }.font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit()).foregroundStyle(.secondary)
        }
    }
    private func time(_ value: Double) -> String {
        let seconds = Int(min(BrowserTab.safeMediaTime(value), 359999))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
