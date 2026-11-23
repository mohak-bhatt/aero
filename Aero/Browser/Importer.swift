import AppKit
import SQLite3
import UniformTypeIdentifiers

/// Imports bookmarks from other browsers (their bookmark files or an exported HTML file).
@MainActor
enum Importer {
    enum Source: String, CaseIterable, Identifiable {
        case safari = "Safari", chrome = "Google Chrome", arc = "Arc", brave = "Brave"
        case edge = "Microsoft Edge", opera = "Opera", vivaldi = "Vivaldi", firefox = "Firefox"
        case html = "Bookmarks HTML File"
        var id: String { rawValue }

        var symbol: String {
            switch self { case .safari: return "safari"; case .firefox: return "flame"; case .html: return "doc.richtext"; default: return "globe" }
        }

        var hint: String {
            switch self {
            case .safari: return "Choose ~/Library/Safari/Bookmarks.plist (macOS may ask for Full Disk Access), or export from Safari: File → Export → Bookmarks… and choose that HTML file."
            case .chrome: return "Choose the “Bookmarks” file in ~/Library/Application Support/Google/Chrome/Default (press ⇧⌘G to type the path)."
            case .arc: return "Choose the “Bookmarks” file in ~/Library/Application Support/Arc/User Data/Default."
            case .brave: return "Choose the “Bookmarks” file in ~/Library/Application Support/BraveSoftware/Brave-Browser/Default."
            case .edge: return "Choose the “Bookmarks” file in ~/Library/Application Support/Microsoft Edge/Default."
            case .opera: return "Choose the “Bookmarks” file in ~/Library/Application Support/com.operasoftware.Opera."
            case .vivaldi: return "Choose the “Bookmarks” file in ~/Library/Application Support/Vivaldi/Default."
            case .firefox: return "In Firefox: Bookmarks → Manage Bookmarks → Import and Backup → Export Bookmarks to HTML…, then choose that file."
            case .html: return "Choose a bookmarks .html file exported from any browser."
            }
        }
    }

    @discardableResult
    static func run(_ source: Source, into target: BookmarkStore? = nil) -> Int? {
        let store = target ?? BookmarkStore.shared
        let panel = NSOpenPanel()
        panel.message = source.hint
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return nil }

        var nodes: [BookmarkNode] = []
        switch url.pathExtension.lowercased() {
        case "html", "htm": nodes = parseHTML(String(decoding: data, as: UTF8.self))
        case "plist": nodes = parseSafari(data)
        default: nodes = parseChromium(data)
        }
        let count = BookmarkStore.flatten(nodes).count
        guard count > 0 else {
            Prompt.info(title: "Nothing imported", message: "No bookmarks were found in that file.")
            return 0
        }
        store.addNode(BookmarkNode(title: "Imported from \(source.rawValue)", url: nil, iconPNG: nil, children: nodes))
        Prompt.info(title: "Imported \(count) bookmarks", message: "They are in the folder “Imported from \(source.rawValue)”.")
        return count
    }

    // MARK: History and passwords

    static func runPasswords() {
        let panel = NSOpenPanel()
        panel.message = "Choose the CSV you exported from your old browser or password manager (Chrome, Safari, Firefox, Edge, Brave, 1Password, Bitwarden…). Delete the file afterwards."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let count = PasswordStore.shared.importCSV(url)
        Prompt.info(title: count > 0 ? "Imported \(count) passwords" : "Nothing imported",
                    message: count > 0 ? "They are stored in your Mac's Keychain and will autofill on matching sites."
                                       : "That file has no URL, username and password columns.")
    }

    @discardableResult
    static func runHistory(_ source: Source) -> Int? {
        let panel = NSOpenPanel()
        panel.message = historyHint(source)
        panel.prompt = "Import"
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let picked = panel.url else { return nil }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("aero-history-\(UUID().uuidString).db")
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: picked, to: copy)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: copy) }
        let entries = readHistory(at: copy.path)
        HistoryStore.shared.importEntries(entries)
        Prompt.info(title: entries.isEmpty ? "Nothing imported" : "Imported \(entries.count) history items",
                    message: entries.isEmpty ? "That doesn't look like a browser history database." : "They now appear in suggestions and Home.")
        return entries.count
    }

    private static func historyHint(_ source: Source) -> String {
        switch source {
        case .safari: return "Choose ~/Library/Safari/History.db (macOS may ask for Full Disk Access)."
        case .firefox: return "Choose places.sqlite inside ~/Library/Application Support/Firefox/Profiles/<your profile>."
        case .html: return "Choose a browser history database file."
        default: return "Choose the “History” file in the same profile folder as your bookmarks."
        }
    }

    static func readHistory(at path: String) -> [HistoryEntry] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        func hasTable(_ name: String) -> Bool {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE name = '\(name)'", -1, &statement, nil) == SQLITE_OK else { return false }
            return sqlite3_step(statement) == SQLITE_ROW
        }

        let query: String, toDate: (Double) -> Date
        if hasTable("urls") {
            query = "SELECT url, title, visit_count, last_visit_time FROM urls ORDER BY last_visit_time DESC LIMIT 3000"
            toDate = { Date(timeIntervalSince1970: $0 / 1_000_000 - 11_644_473_600) }
        } else if hasTable("history_items") {
            query = "SELECT i.url, COALESCE(v.title, ''), i.visit_count, MAX(v.visit_time) FROM history_items i JOIN history_visits v ON v.history_item = i.id GROUP BY i.id ORDER BY MAX(v.visit_time) DESC LIMIT 3000"
            toDate = { Date(timeIntervalSinceReferenceDate: $0) }
        } else if hasTable("moz_places") {
            query = "SELECT url, COALESCE(title, ''), visit_count, last_visit_date FROM moz_places WHERE visit_count > 0 AND last_visit_date IS NOT NULL ORDER BY last_visit_date DESC LIMIT 3000"
            toDate = { Date(timeIntervalSince1970: $0 / 1_000_000) }
        } else { return [] }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        var result: [HistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let urlText = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: urlText)),
                  url.scheme == "http" || url.scheme == "https" else { continue }
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            result.append(HistoryEntry(url: url, title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
                                       visits: max(1, Int(sqlite3_column_int(statement, 2))),
                                       lastVisit: toDate(sqlite3_column_double(statement, 3))))
        }
        return result
    }

    // MARK: Firefox bookmarks (stored in places.sqlite)

    static func readFirefoxBookmarks(at path: String) -> [BookmarkNode] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "SELECT b.id, b.parent, b.type, COALESCE(b.title, ''), COALESCE(p.url, '') FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk = p.id ORDER BY b.parent, b.position"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        var rows: [(id: Int, parent: Int, type: Int, title: String, url: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((Int(sqlite3_column_int(statement, 0)), Int(sqlite3_column_int(statement, 1)), Int(sqlite3_column_int(statement, 2)),
                         sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
                         sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""))
        }
        func children(of parent: Int) -> [BookmarkNode] {
            rows.filter { $0.parent == parent && ($0.type == 1 || $0.type == 2) && $0.title != "tags" }.compactMap { row in
                if row.type == 2 {
                    let kids = children(of: row.id)
                    return kids.isEmpty ? nil : BookmarkNode(title: row.title, url: nil, iconPNG: nil, children: kids)
                }
                guard let url = URL(string: row.url), url.scheme == "http" || url.scheme == "https" else { return nil }
                return BookmarkNode(title: row.title.isEmpty ? row.url : row.title, url: url, iconPNG: nil, children: nil)
            }
        }
        return children(of: 1)
    }

    // MARK: Parsers

    nonisolated static func parseHTML(_ html: String) -> [BookmarkNode] {
        struct Frame { var title: String; var children: [BookmarkNode] }
        let pattern = #"<H3[^>]*>(.*?)</H3>|<A\s[^>]*HREF="([^"]*)"[^>]*>(.*?)</A>|</DL>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        var stack = [Frame(title: "", children: [])]
        let ns = html as NSString
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            func group(_ index: Int) -> String? {
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : unescape(ns.substring(with: range))
            }
            if let title = group(1) {
                stack.append(Frame(title: title, children: []))
            } else if let href = group(2), let url = URL(string: href) {
                stack[stack.count - 1].children.append(BookmarkNode(title: group(3) ?? href, url: url, iconPNG: nil, children: nil))
            } else if stack.count > 1 {
                let frame = stack.removeLast()
                stack[stack.count - 1].children.append(BookmarkNode(title: frame.title, url: nil, iconPNG: nil, children: frame.children))
            }
        }
        while stack.count > 1 {
            let frame = stack.removeLast()
            stack[stack.count - 1].children.append(BookmarkNode(title: frame.title, url: nil, iconPNG: nil, children: frame.children))
        }
        return stack[0].children
    }

    nonisolated static func parseChromium(_ data: Data) -> [BookmarkNode] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [] }
        func node(_ dict: [String: Any]) -> BookmarkNode? {
            let name = dict["name"] as? String ?? ""
            if (dict["type"] as? String) == "url", let urlString = dict["url"] as? String, let url = URL(string: urlString) {
                return BookmarkNode(title: name.isEmpty ? urlString : name, url: url, iconPNG: nil, children: nil)
            }
            if let kids = dict["children"] as? [[String: Any]] {
                return BookmarkNode(title: name, url: nil, iconPNG: nil, children: kids.compactMap(node))
            }
            return nil
        }
        return ["bookmark_bar", "other", "synced"].compactMap { key in
            (roots[key] as? [String: Any]).flatMap(node).flatMap { ($0.children ?? []).isEmpty ? nil : $0 }
        }
    }

    nonisolated static func parseSafari(_ data: Data) -> [BookmarkNode] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let children = root["Children"] as? [[String: Any]] else { return [] }
        func node(_ dict: [String: Any]) -> BookmarkNode? {
            switch dict["WebBookmarkType"] as? String {
            case "WebBookmarkTypeLeaf":
                guard let urlString = dict["URLString"] as? String, let url = URL(string: urlString) else { return nil }
                let title = (dict["URIDictionary"] as? [String: Any])?["title"] as? String ?? urlString
                return BookmarkNode(title: title, url: url, iconPNG: nil, children: nil)
            case "WebBookmarkTypeList":
                let title = dict["Title"] as? String ?? ""
                if title == "com.apple.ReadingList" || title == "History" { return nil }
                let kids = (dict["Children"] as? [[String: Any]] ?? []).compactMap(node)
                return BookmarkNode(title: title == "BookmarksBar" ? "Favorites" : title, url: nil, iconPNG: nil, children: kids)
            default: return nil
            }
        }
        return children.compactMap(node)
    }

    nonisolated private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
