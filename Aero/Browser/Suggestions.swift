import AppKit

struct Suggestion: Identifiable {
    enum Kind { case url, search, web, history, tab, favorite, bookmark }
    let id = UUID()
    let kind: Kind
    let title: String
    var subtitle: String? = nil
    var url: URL? = nil
    var tabID: UUID? = nil
    var query: String? = nil

    var symbol: String {
        switch kind {
        case .url: return "arrow.up.right.circle"
        case .search, .web: return "magnifyingglass"
        case .history: return "clock"
        case .tab: return "square.on.square"
        case .favorite: return "star"
        case .bookmark: return "book"
        }
    }
}

extension BrowserState {
    func updateSuggestions(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestTask?.cancel()
        guard !q.isEmpty else { clearSuggestions(); return }
        suggestionQuery = q
        var list: [Suggestion] = []

        if let url = URLResolver.resolve(q), !url.absoluteString.hasPrefix(Pref.engine.searchBase) {
            list.append(Suggestion(kind: .url, title: url.host ?? url.absoluteString, subtitle: "Go to website", url: url))
        }
        list.append(Suggestion(kind: .search, title: q, subtitle: "Search \(Pref.engine.name)", query: q))

        func matches(_ value: String) -> Bool { value.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        var seen = Set(list.compactMap { $0.url?.absoluteString })

        if Pref.bool(Pref.sugTabsKey, default: true) {
            for tab in tabs.tabs where tab.id != tabs.selectedID && (matches(tab.displayTitle) || matches(tab.url?.absoluteString ?? "")) {
                list.append(Suggestion(kind: .tab, title: tab.displayTitle, subtitle: "Switch to tab", url: tab.url, tabID: tab.id))
                if list.filter({ $0.kind == .tab }).count >= 3 { break }
            }
        }
        if Pref.bool(Pref.sugBookmarksKey, default: true) {
            for fav in favorites.items where matches(fav.title) || matches(fav.url.absoluteString) {
                if seen.insert(fav.url.absoluteString).inserted {
                    list.append(Suggestion(kind: .favorite, title: fav.title, subtitle: fav.url.host, url: fav.url))
                }
                if list.filter({ $0.kind == .favorite }).count >= 2 { break }
            }
            for node in bookmarks.search(q, limit: 3) {
                if let url = node.url, seen.insert(url.absoluteString).inserted {
                    list.append(Suggestion(kind: .bookmark, title: node.title, subtitle: url.host, url: url))
                }
            }
        }
        if Pref.bool(Pref.sugHistoryKey, default: true) {
            for entry in history.search(q, limit: 6) where seen.insert(entry.url.absoluteString).inserted {
                list.append(Suggestion(kind: .history, title: entry.title, subtitle: entry.url.host, url: entry.url))
                if list.filter({ $0.kind == .history }).count >= 4 { break }
            }
        }
        suggestions = Array(list.prefix(9))
        suggestionIndex = nil

        if Pref.bool(Pref.sugWebKey, default: true), q.count >= 2 {
            suggestTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                let words = await Self.fetchWebSuggestions(q)
                guard !Task.isCancelled, let self, self.suggestionQuery == q else { return }
                for word in words where word.lowercased() != q.lowercased() && self.suggestions.count < 11 {
                    if !self.suggestions.contains(where: { $0.title.lowercased() == word.lowercased() }) {
                        self.suggestions.append(Suggestion(kind: .web, title: word, query: word))
                    }
                }
            }
        }
    }

    nonisolated static func fetchWebSuggestions(_ query: String) async -> [String] {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "q", value: query)]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let words = json[1] as? [String] else { return [] }
        return Array(words.prefix(5))
    }

    func moveSuggestion(by delta: Int) {
        guard !suggestions.isEmpty else { return }
        let count = suggestions.count
        if let index = suggestionIndex { suggestionIndex = (index + delta + count) % count }
        else { suggestionIndex = delta > 0 ? 0 : count - 1 }
    }

    func clearSuggestions() {
        suggestTask?.cancel()
        suggestions = []
        suggestionIndex = nil
    }

    func choose(_ suggestion: Suggestion) {
        switch suggestion.kind {
        case .tab:
            if let id = suggestion.tabID, let tab = tabs.tabs.first(where: { $0.id == id }) { tabs.selectTab(tab) }
        case .search, .web:
            if let query = suggestion.query, let url = URLResolver.searchURL(for: query) { openURL(url) }
        default:
            if let url = suggestion.url { openURL(url) }
        }
        clearSuggestions()
        window?.makeFirstResponder(nil)
    }
}
