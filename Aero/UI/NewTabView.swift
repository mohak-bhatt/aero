import SwiftUI

/// New tab page: greeting, search, favourites and most-visited sites.
struct NewTabView: View {
    @ObservedObject var state: BrowserState
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @State private var query = ""
    @FocusState private var focused: Bool

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.10), Color.clear],
                           startPoint: .top, endPoint: .center)
                .background(Color(nsColor: .windowBackgroundColor))

            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Text(greeting).font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text(Date.now.formatted(date: .complete, time: .omitted))
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search \(Pref.engine.name) or enter a website", text: $query)
                            .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                            .onSubmit { state.submit(query); query = "" }
                    }
                    .padding(.horizontal, 18).frame(height: 48).frame(maxWidth: 560)
                    .glass(in: Capsule())

                    if !favorites.items.isEmpty {
                        section("Favorites") {
                            ForEach(favorites.items) { favorite in
                                SiteTile(title: favorite.title, host: favorite.url.host, iconData: favorite.iconPNG) {
                                    state.openFavorite(favorite)
                                }
                            }
                        }
                    }

                    let frequent = history.frequent(8)
                    if !frequent.isEmpty {
                        section("Frequently Visited") {
                            ForEach(frequent) { entry in
                                SiteTile(title: entry.title, host: entry.url.host, iconData: nil) { state.openURL(entry.url) }
                            }
                        }
                    }
                }
                .frame(maxWidth: 680)
                .padding(.top, 96).padding(.bottom, 40).padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focused = true }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 14), count: 6), alignment: .leading, spacing: 16) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
