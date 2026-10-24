//
//  UpdateNowButton.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import SwiftUI

/// Blue "Update Now" pill shown above Downloads / Bookmarks / Share when a newer build exists.
struct UpdateNowButton: View {
    @ObservedObject private var updates = UpdateManager.shared
    var compact = false

    var body: some View {
        if updates.status == .available || updates.status == .installing {
            let installing = updates.status == .installing
            Button { updates.install() } label: {
                HStack(spacing: 6) {
                    if installing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle.fill") }
                    Text(installing ? "Updating…" : "Update Now")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: compact ? 28 : 34)
                .frame(maxWidth: compact ? nil : .infinity)
                .background(Capsule().fill(Color.blue.opacity(0.9)))
                .glass(in: Capsule(), interactive: true)
            }
            .buttonStyle(RubberButtonStyle())
            .disabled(installing)
            .help("Aero \(updates.release?.version ?? "") is available")
        }
    }
}

@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: AboutView())
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AboutView: View {
    @ObservedObject private var updates = UpdateManager.shared

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            Text("Aero").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Version \(updates.currentVersion) (\(updates.buildNumber))")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            Group {
                switch updates.status {
                case .idle: Text(" ")
                case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking for updates…") }
                case .upToDate: Label("Aero is up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .available: Text("Aero \(updates.release?.version ?? "") is available").foregroundStyle(.blue)
                case .installing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing update…") }
                case .failed(let message): Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .font(.system(size: 12.5))
            .frame(minHeight: 34)

            if updates.status == .available || updates.status == .installing {
                UpdateNowButton().padding(.horizontal, 60)
            } else {
                Button("Check for Updates") { updates.check(userInitiated: true) }
                    .disabled(updates.status == .checking)
            }

            Text("Alpha build — thanks for testing.")
                .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .padding(28)
        .frame(width: 360, height: 360)
        .background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
    }
}