import SwiftUI

/// Home: translucent like the sidebar, a search box, and widgets you can turn on or off.
struct NewTabView: View {
    @ObservedObject var state: BrowserState
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared

    @AppStorage("aero.home.favorites") private var showFavorites = true
    @AppStorage("aero.home.frequent") private var showFrequent = true
    @AppStorage("aero.home.bookmarks") private var showBookmarks = false
    @AppStorage("aero.home.recent") private var showRecent = false
    @AppStorage("aero.home.clock") private var showClock = false
    @AppStorage("aero.home.notes") private var showNotes = false
    @AppStorage("aero.home.notesText") private var notesText = ""
    @AppStorage(Pref.blurKey) private var blur = 0.85

    @State private var query = ""
    @State private var customizing = false
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: 78, maximum: 78), spacing: 14)]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SidebarBackground(tint: nil, isOverlay: false).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    searchField
                    if showClock { clockWidget }
                    if showFavorites, !favorites.items.isEmpty {
                        section("Favorites") {
                            ForEach(favorites.items) { favorite in
                                SiteTile(title: favorite.title, host: favorite.url.host, iconData: favorite.iconPNG) { state.openFavorite(favorite) }
                            }
                        }
                    }
                    if showFrequent, !history.frequent(6).isEmpty {
                        section("Frequently Visited") {
                            ForEach(history.frequent(12)) { entry in
                                SiteTile(title: entry.title, host: entry.url.host, iconData: nil) { state.openURL(entry.url) }
                            }
                        }
                    }
                    if showBookmarks, !bookmarks.items.isEmpty {
                        section("Bookmarks") {
                            ForEach(BookmarkStore.flatten(bookmarks.items).prefix(12)) { node in
                                SiteTile(title: node.title, host: node.url?.host, iconData: node.iconPNG) { state.openBookmark(node, inNewTab: false) }
                            }
                        }
                    }
                    if showRecent, !history.entries.isEmpty { recentWidget }
                    if showNotes { notesWidget }
                }
                .frame(maxWidth: 560)
                .padding(.top, 120).padding(.bottom, 40).padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }

            Button { customizing.toggle() } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .medium))
                    .frame(width: 36, height: 36).glass(in: Circle(), interactive: true).contentShape(Circle())
            }
            .buttonStyle(RubberButtonStyle())
            .help("Customize Home")
            .padding(.top, state.layout == .vertical ? max(10, state.rowHeight / 2 - 18) : 14)
            .padding(.trailing, 16)
            .popover(isPresented: $customizing, arrowEdge: .bottom) { customizeMenu }
        }
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(Pref.engine.name) or enter a website", text: $query)
                .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                .onSubmit { state.submit(query); query = "" }
        }
        .padding(.horizontal, 18).frame(height: 48).frame(maxWidth: .infinity)
        .glass(in: Capsule())
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clockWidget: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                Text(context.date, style: .time).font(.system(size: 52, weight: .thin, design: .rounded))
                Text(context.date.formatted(date: .complete, time: .omitted)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .glass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var recentWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(history.recent(6)) { entry in
                    Button { state.openURL(entry.url) } label: {
                        HStack {
                            Text(entry.title).lineLimit(1)
                            Spacer()
                            Text(entry.url.host ?? "").foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.system(size: 12.5)).padding(.horizontal, 14).frame(height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notesWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextEditor(text: $notesText)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(10).frame(height: 130)
                .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customizeMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Customize Home").font(.system(size: 13, weight: .semibold))
            Toggle("Favorites", isOn: $showFavorites)
            Toggle("Frequently Visited", isOn: $showFrequent)
            Toggle("Bookmarks", isOn: $showBookmarks)
            Toggle("Recent History", isOn: $showRecent)
            Toggle("Clock", isOn: $showClock)
            Toggle("Notes", isOn: $showNotes)
            Divider()
            Text("Background blur").font(.system(size: 12)).foregroundStyle(.secondary)
            Slider(value: $blur, in: 0.1...1)
        }
        .font(.system(size: 12.5))
        .padding(14).frame(width: 220)
    }
}

private struct SiteTile: View {
    let title: String
    let host: String?
    let iconData: Data?
    let action: () -> Void

    private var letter: String { String((host ?? title).replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased() }
    private var hue: Double { Double(abs((host ?? title).hashValue) % 360) / 360 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let iconData, let image = NSImage(data: iconData) {
                        Image(nsImage: image).resizable().interpolation(.high).frame(width: 28, height: 28)
                    } else {
                        Text(letter).font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(hue: hue, saturation: 0.55, brightness: 0.85))
                    }
                }
                .frame(width: 60, height: 60)
                .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
                Text((host ?? title).replacingOccurrences(of: "www.", with: ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 78)
            }
        }
        .buttonStyle(RubberButtonStyle())
        .help(title)
    }
}
