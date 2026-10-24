import Foundation
import Combine

struct BookmarkNode: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: URL?
    var iconPNG: Data?
    var children: [BookmarkNode]?
    var isFolder: Bool { url == nil }
}

@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()
    private let key = "aero.bookmarks.v1"

    @Published var items: [BookmarkNode] = [] {
        didSet { if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) } }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([BookmarkNode].self, from: data) { items = decoded }
    }

    func addBookmark(title: String, url: URL, icon: Data?, to folder: UUID? = nil) {
        insert(BookmarkNode(title: title, url: url, iconPNG: icon, children: nil), into: folder)
    }

    func addFolder(title: String, to folder: UUID? = nil) {
        insert(BookmarkNode(title: title, url: nil, iconPNG: nil, children: []), into: folder)
    }

    func addNode(_ node: BookmarkNode) { items.append(node) }

    func rename(_ id: UUID, to title: String) { update(id) { $0.title = title } }

    func delete(_ id: UUID) { _ = take(id) }

    func move(_ id: UUID, to folder: UUID?) {
        guard id != folder, let node = Self.find(items, id) else { return }
        if let folder, Self.contains(node, folder) { return }
        guard let taken = take(id) else { return }
        insert(taken, into: folder)
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return Self.flatten(items).contains { $0.url?.absoluteString == url.absoluteString }
    }

    func folderList() -> [(id: UUID, title: String, depth: Int)] {
        var result: [(UUID, String, Int)] = []
        func walk(_ nodes: [BookmarkNode], _ depth: Int) {
            for node in nodes where node.isFolder {
                result.append((node.id, node.title, depth))
                walk(node.children ?? [], depth + 1)
            }
        }
        walk(items, 0)
        return result.map { (id: $0.0, title: $0.1, depth: $0.2) }
    }

    func search(_ query: String, limit: Int) -> [BookmarkNode] {
        Self.flatten(items).filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || ($0.url?.absoluteString.range(of: query, options: .caseInsensitive) != nil)
        }.prefix(limit).map { $0 }
    }

    // MARK: Tree helpers

    private func insert(_ node: BookmarkNode, into folder: UUID?) {
        guard let folder else { items.append(node); return }
        var copy = items
        if Self.mutate(&copy, folder, { $0.children = ($0.children ?? []) + [node] }) { items = copy } else { items.append(node) }
    }

    private func update(_ id: UUID, _ body: (inout BookmarkNode) -> Void) {
        var copy = items
        if Self.mutate(&copy, id, body) { items = copy }
    }

    private func take(_ id: UUID) -> BookmarkNode? {
        var copy = items
        let removed = Self.remove(&copy, id)
        if removed != nil { items = copy }
        return removed
    }

    private static func mutate(_ nodes: inout [BookmarkNode], _ id: UUID, _ body: (inout BookmarkNode) -> Void) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id { body(&nodes[index]); return true }
            if var kids = nodes[index].children, mutate(&kids, id, body) { nodes[index].children = kids; return true }
        }
        return false
    }

    private static func remove(_ nodes: inout [BookmarkNode], _ id: UUID) -> BookmarkNode? {
        if let index = nodes.firstIndex(where: { $0.id == id }) { return nodes.remove(at: index) }
        for index in nodes.indices {
            if var kids = nodes[index].children, let removed = remove(&kids, id) {
                nodes[index].children = kids
                return removed
            }
        }
        return nil
    }

    private static func find(_ nodes: [BookmarkNode], _ id: UUID) -> BookmarkNode? {
        for node in nodes {
            if node.id == id { return node }
            if let kids = node.children, let found = find(kids, id) { return found }
        }
        return nil
    }

    private static func contains(_ node: BookmarkNode, _ id: UUID) -> Bool {
        node.id == id || (node.children ?? []).contains { contains($0, id) }
    }

    static func flatten(_ nodes: [BookmarkNode]) -> [BookmarkNode] {
        nodes.flatMap { $0.isFolder ? flatten($0.children ?? []) : [$0] }
    }
}
