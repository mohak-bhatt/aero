//
//  NavigationPill.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import SwiftUI

/// Back / forward in one interactive glass pill.
struct NavigationPill: View {
    @ObservedObject var tab: BrowserTab
    let height: CGFloat
    let iconSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.left", enabled: tab.canGoBack, help: "Back (⌘[)") { tab.goBack() }
            Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 0.5, height: height * 0.45)
            button("chevron.right", enabled: tab.canGoForward, help: "Forward (⌘])") { tab.goForward() }
        }
        .glass(in: Capsule(), interactive: true)
    }

    private func button(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: height * 0.95, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(RubberButtonStyle())
        .opacity(enabled ? 0.9 : 0.3)
        .disabled(!enabled)
        .help(help)
    }
}

struct DownloadsButton: View {
    let diameter: CGFloat
    let iconSize: CGFloat
    @ObservedObject private var downloads = DownloadManager.shared
    @State private var open = false

    var body: some View {
        GlassButton(.circle, help: "Downloads", width: diameter, action: { open.toggle() }) {
            ZStack {
                Image(systemName: "arrow.down.circle").font(.system(size: iconSize, weight: .medium))
                if let active = downloads.activeItems.first {
                    ProgressView(value: active.progress).progressViewStyle(.circular).controlSize(.small)
                }
            }
        }
        .popover(isPresented: $open, arrowEdge: .top) { DownloadsPopover(manager: downloads) }
    }
}

struct ShareButton: View {
    let url: URL?
    let diameter: CGFloat
    let iconSize: CGFloat

    var body: some View {
        if let url, url.scheme?.hasPrefix("http") == true {
            GlassShareLink(url: url, diameter: diameter, iconSize: iconSize)
        } else {
            GlassButton(.circle, help: "Share", width: diameter, action: {}) {
                Image(systemName: "square.and.arrow.up").font(.system(size: iconSize, weight: .medium))
            }
            .disabled(true)
            .opacity(0.4)
        }
    }
}

/// Icon-only sidebar / layout toggle, placed one traffic-light gap after the green button.
struct ChromeToggleButton: View {
    let iconSize: CGFloat
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: iconSize, weight: .medium))
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}