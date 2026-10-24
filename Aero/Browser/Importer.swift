import AppKit

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
