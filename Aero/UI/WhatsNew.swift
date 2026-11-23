//
//  WhatsNewItem.swift
//  Aero
//
//  Created by Mohak Bhatt on 13/11/26.
//


import AVKit
import SwiftUI

struct WhatsNewItem: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
}

struct WhatsNewRelease {
    let headline: String
    let subtitle: String
    let items: [WhatsNewItem]
}

/// Release notes shown once after an update. To add real visuals, put files named
/// `whatsnew-<version>-<n>.png` (or .jpg/.gif/.mp4/.mov), n starting at 1, into the Xcode project
/// (target Aero). A video/screenshot with that name replaces the drawn illustration for item n.
enum WhatsNew {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    static func release(for version: String) -> WhatsNewRelease? {
        switch version {
        case "0.2.0":
            return WhatsNewRelease(
                headline: "What’s new in Aero 0.2.0",
                subtitle: "A smaller sidebar. Connected tabs. Live controls within reach.",
                items: [
                    WhatsNewItem(symbol: "sidebar.left", title: "Compact Vertical", detail: "Resize the sidebar into a narrow rail and drag it back to expand. Hold the sidebar button for layout options.", tint: .indigo),
                    WhatsNewItem(symbol: "rectangle.on.rectangle", title: "Connected tab controls", detail: "Preview and close open favourites, pins and tabs on hover. Split tabs stay separate, with numbered pane indicators. A blue audio badge mutes detected HTML media.", tint: .blue),
                    WhatsNewItem(symbol: "slider.horizontal.3", title: "A swipe-away menu", detail: "Swipe right with two fingers over the sidebar for timers, clocks, history, bookmarks, downloads and settings.", tint: .orange),
                    WhatsNewItem(symbol: "waveform", title: "Live Activities", detail: "Compact activity indicators expand on hover. Media controls, artwork and progress stay close; dismiss activities from their menu.", tint: .pink),
                    WhatsNewItem(symbol: "arrow.clockwise", title: "Fluid refresh", detail: "Pull down with two fingers at the page top, then release to reload. Tabs keep their favicon inside a loading ring.", tint: .mint),
                    WhatsNewItem(symbol: "checkmark.shield", title: "Reliability foundations", detail: "Credential-origin checks, safer release links, regression tests and automated build checks. Aero remains a preview, with known limitations documented in the release notes.", tint: .teal)
                ])
        case "0.1.3":
            return WhatsNewRelease(
                headline: "What’s new in Aero 0.1.3",
                subtitle: "A calmer, sidebar-first Aero with split view, live media and one-click import.",
                items: [
                    WhatsNewItem(symbol: "rectangle.split.2x1", title: "Split View",
                                 detail: "Drag a tab onto the page and a soft preview shows where it will land. Two tabs go side by side, three become columns, four make a grid.",
                                 tint: .blue),
                    WhatsNewItem(symbol: "play.rectangle.fill", title: "Live video in the sidebar",
                                 detail: "Switch tabs and the video keeps playing right in the sidebar. Hover over it and the controls slide up underneath.",
                                 tint: .red),
                    WhatsNewItem(symbol: "music.note", title: "Now Playing",
                                 detail: "Music from any tab gets a player just like the one in your menu bar: artwork, previous, play and next, and progress.",
                                 tint: .pink),
                    WhatsNewItem(symbol: "eye", title: "Tab previews",
                                 detail: "Hold your pointer over a tab to peek at its page, shown beside the sidebar.",
                                 tint: .teal),
                    WhatsNewItem(symbol: "square.and.arrow.down", title: "Import in one click",
                                 detail: "Aero finds Chrome, Arc, Brave, Edge, Firefox and Safari on your Mac. Pick one and bring over bookmarks, history and passwords.",
                                 tint: .orange),
                    WhatsNewItem(symbol: "puzzlepiece.extension", title: "Extensions",
                                 detail: "Safari extensions already on your Mac appear under the puzzle button, one click to add.",
                                 tint: .purple),
                    WhatsNewItem(symbol: "house", title: "A better Home",
                                 detail: "Search with suggestions, and add favorites, frequently visited sites, a clock or notes. Tap the sliders button to customize.",
                                 tint: .green),
                    WhatsNewItem(symbol: "sidebar.left", title: "Simpler by design",
                                 detail: "Aero is now sidebar-only, so everything feels faster and more focused.",
                                 tint: .indigo)
                ])
        default:
            return nil
        }
    }
}

@MainActor
enum WhatsNewWindow {
    private static var window: NSWindow?
    private static let seenKey = "aero.lastSeenVersion"

    /// Opens after an update. Brand-new installs get the welcome tour instead.
    static func showIfNeeded() {
        let defaults = UserDefaults.standard
        let current = WhatsNew.version
        let last = defaults.string(forKey: seenKey)
        defaults.set(current, forKey: seenKey)
        guard !Onboarding.needed, last != current, WhatsNew.release(for: current) != nil else { return }
        show()
    }

    static func show() {
        guard let release = WhatsNew.release(for: WhatsNew.version) else {
            Prompt.info(title: "You’re up to date", message: "There are no release notes for this version.")
            return
        }
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: WhatsNewView(release: release, version: WhatsNew.version, close: { window?.close() }))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WhatsNewView: View {
    let release: WhatsNewRelease
    let version: String
    let close: () -> Void
    @State private var step = 0

    private var total: Int { release.items.count + 1 }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if step == 0 { intro } else { feature(release.items[step - 1], number: step) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 44).padding(.top, 52)
            .id(step)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            footer
        }
        .frame(width: 640, height: 620)
        .background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 104, height: 104)
            Text(release.headline).font(.system(size: 28, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
            Text(release.subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Version \(version)").font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(.top, 50)
    }

    private func feature(_ item: WhatsNewItem, number: Int) -> some View {
        VStack(spacing: 20) {
            WhatsNewMedia(item: item, name: "whatsnew-\(version)-\(number)")
            VStack(spacing: 6) {
                Text(item.title).font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(item.detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                GlassButton(.capsule, help: "Back", width: 96, height: 36, action: { step -= 1 }) { Text("Back") }
            } else {
                Color.clear.frame(width: 96, height: 36)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Circle().fill(index == step ? Color.accentColor : Color.primary.opacity(0.2)).frame(width: 7, height: 7)
                }
            }
            Spacer()
            GlassButton(.capsule, help: step == total - 1 ? "Done" : "Next", width: 112, height: 36,
                        action: { if step == total - 1 { close() } else { step += 1 } }) {
                Text(step == total - 1 ? "Done" : "Next").fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 36).padding(.bottom, 28)
    }
}

/// Screenshot or video from the app bundle when present; otherwise a drawn illustration.
private struct WhatsNewMedia: View {
    let item: WhatsNewItem
    let name: String

    var body: some View {
        Group {
            if let url = Self.url(name, ["mp4", "mov", "m4v"]) {
                LoopingVideo(url: url)
            } else if let url = Self.url(name, ["png", "jpg", "jpeg", "gif", "heic"]), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                illustration
            }
        }
        .frame(maxWidth: .infinity).frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }

    private var illustration: some View {
        ZStack {
            LinearGradient(colors: [item.tint.opacity(0.65), item.tint.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.10)).frame(width: 220).offset(x: 120, y: -70)
            Circle().fill(.white.opacity(0.08)).frame(width: 150).offset(x: -140, y: 90)
            Image(systemName: item.symbol)
                .font(.system(size: 88, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .padding(44)
                .glass(in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
    }

    private static func url(_ name: String, _ extensions: [String]) -> URL? {
        for ext in extensions { if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url } }
        return nil
    }
}

private struct LoopingVideo: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let player = AVPlayer(url: url)
        player.isMuted = true
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}
