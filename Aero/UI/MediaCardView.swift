//
//  MediaCardView.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import SwiftUI

/// Sidebar mini-player: appears above the bottom buttons when a background tab plays audio or video.
struct MediaCardView: View {
    @ObservedObject private var hub = MediaHub.shared
    let tabs: TabManager

    var body: some View {
        if let source = source {
            MediaCard(tab: source.tab, info: source.info) { tabs.selectTab(source.tab) }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var source: (tab: BrowserTab, info: MediaInfo)? {
        for id in hub.order where id != tabs.selectedID {
            if let tab = tabs.tabs.first(where: { $0.id == id }), let info = hub.items[id] { return (tab, info) }
        }
        return nil
    }
}

private struct MediaCard: View {
    @ObservedObject var tab: BrowserTab
    let info: MediaInfo
    let goToTab: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            if info.isVideo { videoPreview } else { audioHeader }
            if info.duration > 0 {
                ProgressView(value: min(info.currentTime, info.duration), total: info.duration)
                    .progressViewStyle(.linear).controlSize(.small)
            }
            if !info.isVideo { controls }
        }
        .padding(10)
        .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
    }

    private var videoPreview: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let image = tab.snapshot {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else if let url = info.artworkURL {
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.primary.opacity(0.1) }
                } else {
                    Color.primary.opacity(0.1)
                }
            }
            .frame(height: 96).frame(maxWidth: .infinity).clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(info.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    .padding(.horizontal, 8).padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hovering { controls.padding(.bottom, 6).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .padding(.top, 4)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var audioHeader: some View {
        HStack(spacing: 10) {
            Group {
                if let url = info.artworkURL {
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.primary.opacity(0.1) }
                } else {
                    Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(info.artist).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            button("gobackward.10", "Back 10 seconds") { tab.mediaCommand("back10") }
            button(info.isPlaying ? "pause.fill" : "play.fill", info.isPlaying ? "Pause" : "Play", size: 17) { tab.mediaCommand("toggle") }
            button("goforward.10", "Forward 10 seconds") { tab.mediaCommand("fwd10") }
            if info.isVideo {
                button("pip.enter", "Picture in Picture") { tab.mediaCommand("pip") }
            }
            button("arrow.up.right.square", "Go to Tab", action: goToTab)
        }
        .frame(maxWidth: .infinity)
    }

    private func button(_ symbol: String, _ help: String, size: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .medium)).frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(RubberButtonStyle())
        .help(help)
    }
}
