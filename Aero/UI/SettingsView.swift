import SwiftUI

/// Settings (⌘,): toolbar-style tabs like Safari's.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            AppearancePane().tabItem { Label("Appearance", systemImage: "sidebar.left") }
            SearchPane().tabItem { Label("Search", systemImage: "magnifyingglass") }
            WebsitesPane().tabItem { Label("Websites", systemImage: "globe") }
            PrivacyPane().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 540, height: 440)
    }
}

private struct GeneralPane: View {
    @AppStorage(Pref.engineKey) private var engine = SearchEngine.google.rawValue
    @AppStorage(Pref.domainOnlyKey) private var domainOnly = true
    @AppStorage(Pref.barKey) private var bookmarksBar = true

    var body: some View {
        Form {
            Picker("Search engine", selection: $engine) {
                ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Toggle("Show only the website domain in the address bar", isOn: $domainOnly)
            Toggle("Show bookmarks bar (horizontal tabs)", isOn: $bookmarksBar)
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
    @AppStorage(Pref.layoutKey) private var layout = "horizontal"
    @AppStorage(Pref.sidebarSizeKey) private var sizeChoice = 0
    @AppStorage(Pref.tintKey) private var tint = true
    @AppStorage(Pref.blurKey) private var blur = 0.85

    var body: some View {
        Form {
            Picker("Tab layout", selection: $layout) {
                Text("Horizontal tabs").tag("horizontal")
                Text("Vertical tabs").tag("vertical")
            }
            Picker("Sidebar size", selection: $sizeChoice) {
                Text("Automatic (system setting)").tag(0)
                Text("Small").tag(1)
                Text("Medium").tag(2)
                Text("Large").tag(3)
            }
            Toggle("Tint the sidebar with the website's colour", isOn: $tint)
            VStack(alignment: .leading) {
                Text("Background blur")
                Slider(value: $blur, in: 0.1...1) { Text("Background blur") } minimumValueLabel: { Text("Clear") } maximumValueLabel: { Text("Frosted") }
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
                                .buttonStyle(.plain).foregroundStyle(.secondary)
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
