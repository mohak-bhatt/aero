//
//  NavigationPill.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import SwiftUI
import AppKit

/// Unframed navigation controls sized to match the sidebar toggle.
struct NavigationPill: View {
    @ObservedObject var tab: BrowserTab
    let height: CGFloat
    let iconSize: CGFloat
    var vertical = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            button("chevron.left", enabled: tab.canGoBack, help: "Back (⌘[)") { tab.goBack() }
            button("chevron.right", enabled: tab.canGoForward, help: "Forward (⌘])") { tab.goForward() }
        }
    }

    private func button(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: height * 0.95, height: height)
                .contentShape(Rectangle())
        }
        .keyframeAnimator(initialValue: CGFloat(1), trigger: reduceMotion ? 0 : (symbol == "chevron.left" ? tab.backPulse : tab.forwardPulse)) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            CubicKeyframe(1.32, duration: 0.10)
            SpringKeyframe(1, duration: 0.32, spring: .bouncy)
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
    @EnvironmentObject private var state: BrowserState
    @State private var optionsOpen = false

    var body: some View {
        SidebarNativeButton(iconSize: iconSize, click: action, hold: { optionsOpen = true })
            .frame(width: 30, height: 30)
            .accessibilityLabel("Sidebar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityAction(named: "Layout options") { optionsOpen = true }
            .help(help + ". Hold or force-click for layout options.")
            .contextMenu { layoutOptions }
            .popover(isPresented: $optionsOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Browser Layout").font(.headline)
                    ForEach([BrowserLayout.Preset.classic, .compact]) { preset in
                        Button {
                            optionsOpen = false
                            state.applyLayout(preset)
                        } label: {
                            HStack {
                                Text(preset.title)
                                Spacer()
                                if state.layoutPreset == preset { Image(systemName: "checkmark") }
                            }.frame(width: 190)
                        }.buttonStyle(.borderless)
                    }
                    Divider()
                    Button("Customise Browser…") { optionsOpen = false; state.engineEditing = true }
                    Button(state.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { optionsOpen = false; state.toggleSidebar() }
                }.padding(16)
            }
    }
    @ViewBuilder private var layoutOptions: some View {
        ForEach([BrowserLayout.Preset.classic, .compact]) { preset in
            Button(preset.title) { state.applyLayout(preset) }
        }
        Divider()
        Button("Customise Browser…") { state.engineEditing = true }
    }
}

private struct SidebarNativeButton: NSViewRepresentable {
    let iconSize: CGFloat
    let click: () -> Void
    let hold: () -> Void
    func makeNSView(context: Context) -> HoldButton {
        let button = HoldButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.target = button
        button.action = #selector(HoldButton.activate)
        button.setAccessibilityLabel("Sidebar")
        return button
    }
    func updateNSView(_ button: HoldButton, context: Context) {
        button.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Sidebar")?
            .withSymbolConfiguration(.init(pointSize: iconSize, weight: .medium))
        button.click = click; button.hold = hold
    }
    final class HoldButton: NSButton {
        var click: () -> Void = {}
        var hold: () -> Void = {}
        private var holding = false
        private var holdTimer: Timer?
        private var pressureTriggered = false
        override func mouseDown(with event: NSEvent) {
            holding = true
            let timer = Timer(timeInterval: 0.45, target: self, selector: #selector(reveal), userInfo: nil, repeats: false)
            holdTimer = timer
            RunLoop.main.add(timer, forMode: .eventTracking)
            pressureTriggered = false
            super.mouseDown(with: event)
            holding = false
            holdTimer?.invalidate(); holdTimer = nil
        }
        override func pressureChange(with event: NSEvent) {
            if event.stage >= 2 { reveal() }
            super.pressureChange(with: event)
        }
        @objc private func reveal() {
            guard holding, !pressureTriggered, let window,
                  bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
            pressureTriggered = true
            holdTimer?.invalidate()
            hold()
        }
        @objc func activate() {
            if !pressureTriggered { click() }
        }
    }
}

/// Reuse system buttons so their actions, hover glyphs and accessibility stay native.
struct VerticalTrafficLights: NSViewRepresentable {
    func makeNSView(context: Context) -> Host { Host() }
    func updateNSView(_ view: Host, context: Context) { view.attach() }
    static func dismantleNSView(_ view: Host, coordinator: ()) { view.restore() }
    final class Host: NSView {
        private var originals: [(NSButton, NSView, NSRect, NSView.AutoresizingMask)] = []
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { attach() } }
        func attach() {
            guard let window else { return }
            let currentButtons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
            if !originals.isEmpty && !currentButtons.allSatisfy({ current in originals.contains { $0.0 === current } }) { restore() }
            if !originals.isEmpty {
                for item in originals where item.0.superview !== self { item.0.removeFromSuperview(); addSubview(item.0) }
                needsLayout = true
                return
            }
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
                originals.append((button, parent, button.frame, button.autoresizingMask))
                button.removeFromSuperview()
                button.autoresizingMask = []
                addSubview(button)
                button.isHidden = false
                button.alphaValue = 1
            }
            needsLayout = true
        }
        override func layout() {
            super.layout()
            for (index, item) in originals.enumerated() {
                let button = item.0
                button.setFrameOrigin(NSPoint(x: (bounds.width - button.frame.width) / 2, y: 12 + CGFloat(index) * 24))
            }
        }
        func restore() {
            for (button, parent, frame, mask) in originals {
                button.removeFromSuperview(); parent.addSubview(button)
                button.frame = frame; button.autoresizingMask = mask
            }
            originals.removeAll()
        }
    }
}

@MainActor enum AeroHaptics {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard UserDefaults.standard.object(forKey: "aero.haptics.enabled") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
