//
//  Onboarding.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import SwiftUI

@MainActor
enum Onboarding {
    private static var window: NSWindow?
    static var needed: Bool { !UserDefaults.standard.bool(forKey: "aero.onboarded") }

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(finish: { finish() }))
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: "aero.onboarded")
        window?.close()
        window = nil
    }
}

/// First-run tour: every setting is a choice you make, with the real shortcuts at the end.
struct OnboardingView: View {
    let finish: () -> Void
    @State private var step = 0
    @AppStorage(Pref.layoutKey) private var layout = "horizontal"
    @AppStorage(Pref.sidebarSizeKey) private var sizeChoice = 0
    @AppStorage(Pref.engineKey) private var engine = SearchEngine.google.rawValue
    @AppStorage(Pref.domainOnlyKey) private var domainOnly = true
    @AppStorage(Pref.tintKey) private var tint = true
    @AppStorage(Pref.barKey) private var bar = true

    private let total = 7

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: layoutStep
                case 2: sizeStep
                case 3: searchStep
                case 4: lookStep
                case 5: organizeStep
                default: shortcutsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 44)
            .padding(.top, 54)
            .id(step)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            footer
        }
        .frame(width: 620, height: 560)
        .background(VisualEffectView(material: .underWindowBackground).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 110, height: 110)
            Text("Welcome to Aero").font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("A calm, native browser built on Liquid Glass.\nLet's set it up your way — it takes a minute.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var layoutStep: some View {
        VStack(spacing: 22) {
            header("rectangle.split.2x1", "Choose your tab layout", "You can switch any time with ⌥⌘V.")
            HStack(spacing: 16) {
                OptionCard(selected: layout == "horizontal", action: { layout = "horizontal" }) {
                    LayoutPreview(vertical: false)
                    Text("Horizontal tabs").font(.headline)
                    Text("Tabs along the top, like Safari").font(.caption).foregroundStyle(.secondary)
                }
                OptionCard(selected: layout == "vertical", action: { layout = "vertical" }) {
                    LayoutPreview(vertical: true)
                    Text("Vertical tabs").font(.headline)
                    Text("A sidebar with pins and favorites").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sizeStep: some View {
        VStack(spacing: 22) {
            header("sidebar.left", "Pick a sidebar size", "Matches the sizes in System Settings.")
            HStack(spacing: 12) {
                ForEach([(0, "Automatic", "gearshape"), (1, "Small", "textformat.size.smaller"),
                         (2, "Medium", "textformat.size"), (3, "Large", "textformat.size.larger")], id: \.0) { item in
                    OptionCard(selected: sizeChoice == item.0, action: { sizeChoice = item.0 }) {
                        Image(systemName: item.2).font(.system(size: 26)).frame(height: 40)
                        Text(item.1).font(.system(size: 13, weight: .medium))
                    }
                }
            }
            Text("Automatic follows your Mac's sidebar icon size.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var searchStep: some View {
        VStack(spacing: 22) {
            header("magnifyingglass", "Search and address bar", "Choose your search engine and how addresses look.")
            HStack(spacing: 10) {
                ForEach(SearchEngine.allCases) { item in
                    OptionCard(selected: engine == item.rawValue, action: { engine = item.rawValue }) {
                        Text(item.name).font(.system(size: 13, weight: .medium))
                    }
                }
            }
            HStack(spacing: 16) {
                OptionCard(selected: domainOnly, action: { domainOnly = true }) {
                    Text("github.com").font(.system(size: 14, weight: .medium)); Text("Domain only").font(.caption).foregroundStyle(.secondary)
                }
                OptionCard(selected: !domainOnly, action: { domainOnly = false }) {
                    Text("github.com/aero/browser").font(.system(size: 14, weight: .medium)); Text("Full address").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var lookStep: some View {
        VStack(spacing: 22) {
            header("paintpalette", "Make it yours", "Two small choices about how Aero looks.")
            HStack(spacing: 16) {
                OptionCard(selected: tint, action: { tint = true }) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.55)).frame(height: 54)
                    Text("Tint with the website").font(.system(size: 13, weight: .medium))
                }
                OptionCard(selected: !tint, action: { tint = false }) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.12)).frame(height: 54)
                    Text("Always neutral glass").font(.system(size: 13, weight: .medium))
                }
            }
            HStack(spacing: 16) {
                OptionCard(selected: bar, action: { bar = true }) {
                    Image(systemName: "bookmark").font(.system(size: 22)); Text("Show bookmarks bar").font(.system(size: 13, weight: .medium))
                }
                OptionCard(selected: !bar, action: { bar = false }) {
                    Image(systemName: "bookmark.slash").font(.system(size: 22)); Text("Hide bookmarks bar").font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    private var organizeStep: some View {
        VStack(spacing: 20) {
            header("square.grid.2x2", "Keep things organized", "Right-click any tab to try these.")
            tip("pin", "Pinned tabs", "Small icons that stay put. Five per row.", "⇧⌘P")
            tip("star", "Favorites", "Big glass tiles that open a site in place, like an app.", "⇧⌘D")
            tip("book", "Bookmarks", "Folders you can organize. Open them from the pill at the bottom of the sidebar.", "⌘D")
            tip("clock", "History", "Everything feeds the address bar's suggestions.", "⌘Y")
        }
    }

    private var shortcutsStep: some View {
        VStack(spacing: 18) {
            header("keyboard", "A few shortcuts worth knowing", "You're all set after this.")
            tip("plus", "New tab", "", "⌘T")
            tip("magnifyingglass", "Search or enter address", "", "⌘L")
            tip("arrow.left.arrow.right", "Switch tabs — hold for previews", "", "⌃Tab")
            tip("rectangle.on.rectangle", "Pull a tab out into its own window", "Drag it off the window", "")
            tip("sidebar.left", "Hide the sidebar (hover the edge to peek)", "", "⌃⌘S")
        }
    }

    // MARK: Pieces

    private func header(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String, _ keys: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 34, height: 34)
                .glass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium))
                if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            Spacer()
            if !keys.isEmpty { Text(keys).font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary) }
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
            GlassButton(.capsule, help: step == total - 1 ? "Start browsing" : "Continue", width: 128, height: 36,
                        action: { if step == total - 1 { finish() } else { step += 1 } }) {
                Text(step == total - 1 ? "Start Browsing" : "Continue").fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
    }
}

private struct OptionCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    let content: Content

    init(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) { content }
                .padding(14)
                .frame(maxWidth: .infinity)
                .glass(in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                       tint: selected ? Color.accentColor.opacity(0.3) : nil, interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0)
                        .allowsHitTesting(false)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(RubberButtonStyle())
    }
}

private struct LayoutPreview: View {
    let vertical: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08))
            if vertical {
                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(Color.primary.opacity(0.25)).frame(height: 8)
                        HStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.22)).frame(height: 10) } }
                        ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.14)).frame(height: 9) }
                    }
                    .frame(width: 52)
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06))
                }
                .padding(8)
            } else {
                VStack(spacing: 5) {
                    HStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.2)).frame(height: 9) } }
                    Capsule().fill(Color.primary.opacity(0.25)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06))
                }
                .padding(8)
            }
        }
        .frame(height: 100)
    }
}
