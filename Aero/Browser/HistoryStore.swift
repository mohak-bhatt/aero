//
//  HistoryEntry.swift
//  Aero
//
//  Created by Mohak Bhatt on 24/10/26.
//


import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var url: URL
    var title: String
    var visits: Int
    var lastVisit: Date
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private let key = "aero.history.v1"
    private let limit = 1500

    @Published private(set) var entries: [HistoryEntry] = []   // newest first

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) { entries = decoded }
    }

    func record(url: URL, title: String) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        let name = title.isEmpty ? (url.host ?? url.absoluteString) : title
        if let index = entries.firstIndex(where: { $0.url.absoluteString == url.absoluteString }) {
            var entry = entries.remove(at: index)
            entry.visits += 1; entry.lastVisit = Date(); entry.title = name
            entries.insert(entry, at: 0)
        } else {
            entries.insert(HistoryEntry(url: url, title: name, visits: 1, lastVisit: Date()), at: 0)
            if entries.count > limit { entries.removeLast() }
        }
        save()
    }

    func recent(_ count: Int) -> [HistoryEntry] { Array(entries.prefix(count)) }

    func frequent(_ count: Int) -> [HistoryEntry] {
        var seen = Set<String>()
        return entries.sorted { $0.visits > $1.visits }
            .filter { seen.insert($0.url.host ?? "").inserted }
            .prefix(count).map { $0 }
    }

    func search(_ query: String, limit: Int) -> [HistoryEntry] {
        entries.filter {
            $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.url.absoluteString.range(of: query, options: .caseInsensitive) != nil
        }.prefix(limit).map { $0 }
    }

    func clear() { entries = []; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }
}