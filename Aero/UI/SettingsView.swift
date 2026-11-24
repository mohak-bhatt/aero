import SwiftUI

/// Settings (⌘,): toolbar-style tabs like Safari's.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            EngineSetupView().tabItem { Label("Aero Engine", systemImage: "slider.horizontal.3") }
            AppearancePane().tabItem { Label("Appearance", systemImage: "sidebar.left") }
            SearchPane().tabItem { Label("Search", systemImage: "magnifyingglass") }
            WebsitesPane().tabItem { Label("Websites", systemImage: "globe") }
            PasswordsPane().tabItem { Label("Passwords", systemImage: "key") }
            PrivacyPane().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 540, height: 440)
    }
}

private struct GeneralPane: View {
    @AppStorage(Pref.engineKey) private var engine = SearchEngine.google.rawValue
    @AppStorage(Pref.domainOnlyKey) private var domainOnly = true

    var body: some View {
        Form {
            Picker("Search engine", selection: $engine) {
                ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Toggle("Show only the website domain in the address bar", isOn: $domainOnly)
            Section("Default browser") {
                HStack {
                    Text(DefaultBrowser.isDefault ? "Aero is your default browser" : "Aero is not your default browser")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Make Default") { DefaultBrowser.makeDefault() }.disabled(DefaultBrowser.isDefault)
                }
            }
            Section("Import") {
                Menu("Import Bookmarks From…") {
                    ForEach(Importer.Source.allCases) { source in
                        Button(source.rawValue) { Importer.run(source) }
                    }
                }
            }
            Section("Downloads") {
                LabeledContent("Saved to") { Text("~/Downloads").foregroundStyle(.secondary) }
                Button("Show Downloads in Finder") { Task { @MainActor in DownloadManager.shared.showInFinder() } }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearancePane: View {
    @AppStorage(Pref.sidebarSizeKey) private var sizeChoice = 0
    @AppStorage(Pref.tintKey) private var tint = true
    @AppStorage("aero.glass.intensity") private var blur = 0.85

    var body: some View {
        Form {
            Picker("Sidebar size", selection: $sizeChoice) {
                Text("Automatic (system setting)").tag(0)
                Text("Small").tag(1)
                Text("Medium").tag(2)
                Text("Large").tag(3)
            }
            Toggle("Tint the sidebar with the website's colour", isOn: $tint)
            VStack(alignment: .leading) {
                Text("Background transparency")
                Slider(value: $blur, in: 0...1) { Text("Background transparency") } minimumValueLabel: { Text("Clear") } maximumValueLabel: { Text("Strong") }
                    .labelsHidden().accessibilityLabel("Background transparency")
            }
        }
        .formStyle(.grouped)
    }
}

private struct SearchPane: View {
    @AppStorage(Pref.sugHistoryKey) private var history = true
    @AppStorage(Pref.sugTabsKey) private var tabs = true
    @AppStorage(Pref.sugBookmarksKey) private var bookmarks = true
    @AppStorage(Pref.sugWebKey) private var web = true

    var body: some View {
        Form {
            Section("Address bar suggestions") {
                Toggle("History", isOn: $history)
                Toggle("Open tabs", isOn: $tabs)
                Toggle("Favorites and bookmarks", isOn: $bookmarks)
                Toggle("Search engine suggestions", isOn: $web)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WebsitesPane: View {
    @AppStorage(Pref.defaultZoomKey) private var defaultZoom = 1.0
    @AppStorage(Pref.rememberZoomKey) private var remember = true
    @ObservedObject private var zooms = SiteZoomStore.shared

    private let levels: [Double] = [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        Form {
            Picker("Default page zoom", selection: $defaultZoom) {
                ForEach(levels, id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
            }
            Toggle("Remember the zoom level of each website", isOn: $remember)
            Section("Websites with a custom zoom") {
                if zooms.zooms.isEmpty {
                    Text("None yet. Zoom a page with ⌘+ or ⌘- and Aero will remember it.").foregroundStyle(.secondary)
                } else {
                    ForEach(zooms.zooms.keys.sorted(), id: \.self) { host in
                        HStack {
                            Text(host)
                            Spacer()
                            Text("\(Int((zooms.zooms[host] ?? 1) * 100))%").foregroundStyle(.secondary)
                            Button { zooms.remove(host: host) } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(RubberButtonStyle()).foregroundStyle(.secondary)
                        }
                    }
                    Button("Remove All") { zooms.removeAll() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacyPane: View {
    var body: some View {
        Form {
            Section("History and data") {
                Button("Clear History…") {
                    if Prompt.confirm(title: "Clear history?", message: "Visited pages will be removed from history.", button: "Clear") {
                        HistoryStore.shared.clear()
                    }
                }
                Button("Clear Cookies and Website Data…") {
                    if Prompt.confirm(title: "Clear all website data?", message: "You will be signed out of websites.", button: "Clear") {
                        WebsiteData.clearAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}


private struct PasswordsPane: View {
    @ObservedObject private var store = PasswordStore.shared
    @State private var revealed: [String: String] = [:]

    var body: some View {
        Form {
            Section("Saved passwords") {
                if store.credentials.isEmpty {
                    Text("Nothing saved yet. Aero offers to save passwords when you sign in to a website.").foregroundStyle(.secondary)
                }
                ForEach(store.credentials) { credential in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credential.host)
                            Text(credential.username.isEmpty ? "No username" : credential.username).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let password = revealed[credential.id] {
                            Text(password).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        }
                        Button(revealed[credential.id] == nil ? "Show" : "Hide") {
                            if revealed[credential.id] != nil { revealed[credential.id] = nil; return }
                            Task {
                                if await store.authenticate(reason: "Show the password for \(credential.host)") {
                                    revealed[credential.id] = store.password(host: credential.host, username: credential.username)
                                }
                            }
                        }
                        Button { store.delete(credential); revealed[credential.id] = nil } label: { Image(systemName: "trash") }
                            .buttonStyle(RubberButtonStyle()).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Import") {
                Button("Import Passwords from CSV…") { Importer.runPasswords() }
                Text("Export a CSV from your old browser or password manager, import it here, then delete the file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shared first-run and settings editor. Each control changes a working browser setting.
struct EngineSetupView: View {
    @State private var layout = BrowserLayoutStore().load() ?? BrowserLayout()
    @AppStorage(Pref.tintKey) private var tint = true
    @AppStorage("aero.haptics.enabled") private var haptics = true
    var body: some View {
        Form {
            Section("Make Aero yours") {
                Button("Return to original sidebar") {
                    if let state = WindowCoordinator.shared.activeState { state.engine.finish(cancel: true); state.engine.enabled = false; state.engineEditing = false; state.sidebarVisible = true }
                }
                Text("Aero Engine edits the live browser. Move individual controls to any edge; the same controls work in vertical and horizontal arrangements.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Browser Canvas") {
                    WindowCoordinator.shared.activeState?.engineEditing = true
                    NSApp.keyWindow?.orderOut(nil)
                    WindowCoordinator.shared.activeState?.tabs.selectedTab?.webView.window?.makeKeyAndOrderFront(nil)
                }

                Picker("Starting layout", selection: $layout.preset) {
                    ForEach(BrowserLayout.Preset.shippingCases) { Text($0.title).tag($0) }
                }.onValueChange(of: layout.preset) { preset in
                    layout = BrowserLayout.configuration(for: preset)
                    apply()
                }
                Text("Classic keeps the sidebar visible. Focus reveals it on demand. Compact Vertical keeps tabs in a narrow icon rail.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sidebar") {
                Toggle("Keep sidebar visible", isOn: $layout.sidebarPinned)
                    .onValueChange(of: layout.sidebarPinned) { _ in apply() }
                LabeledContent(layout.preset == .compact ? "Expanded width" : "Width", value: "\(Int(layout.sidebarWidth)) pt")
                Slider(value: $layout.sidebarWidth, in: 200...420, step: 10)
                    .onValueChange(of: layout.sidebarWidth) { _ in apply() }
                    .accessibilityLabel("Sidebar width")
                    .disabled(layout.preset == .compact)
                Toggle("Match website colour", isOn: $tint)
            }
            Section("Interaction") {
                Toggle("Haptic feedback", isOn: $haptics)
                Button("Test Trackpad Feedback") { AeroHaptics.perform(.generic) }.disabled(!haptics)
                Text("Use the Force Touch trackpad to test feedback. macOS controls delivery through the current input device and system preferences.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func apply() {
        let value = layout.validated()
        BrowserLayoutStore().save(value)
        if let state = WindowCoordinator.shared.activeState {
            state.layoutPreset = value.preset
            state.sidebarWidth = value.sidebarWidth
            state.sidebarVisible = value.sidebarPinned
            state.sidebarPeeking = false
        }
    }
}
