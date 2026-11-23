import Foundation
import XCTest
@testable import AeroCore

final class SessionStoreTests: XCTestCase {
    func testRoundTripThenEmptySaveClearsOldTabs() throws {
        let name = "AeroTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionStore(defaults: defaults)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        store.save(SessionSnapshot(entries: [.init(url: url, title: "Example", pinned: true)], selectedIndex: 0))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.entries.first?.url, url)
        XCTAssertEqual(loaded.entries.first?.pinned, true)
        store.save(SessionSnapshot(entries: [], selectedIndex: 0))
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: "aero.session.v1"))
    }

    func testLegacySessionAndCorruptData() throws {
        let name = "AeroTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SessionStore(defaults: defaults)
        defaults.set(Data(#"{"entries":[{"url":"https://example.com","title":"Legacy"}],"selectedIndex":0}"#.utf8), forKey: "aero.session.v1")
        XCTAssertNil(try XCTUnwrap(store.load()).entries.first?.pinned)
        defaults.set(Data("broken".utf8), forKey: "aero.session.v1")
        XCTAssertNil(store.load())
    }

    func testSplitSessionPreservesHomeFavoriteAndActivePane() throws {
        let favorite = UUID()
        let snapshot = SessionSnapshot(entries: [
            .init(url: nil, title: "Home"),
            .init(url: URL(string: "https://example.com"), title: "Favorite", favoriteID: favorite),
            .init(url: URL(string: "https://example.org"), title: "Pinned", pinned: true)
        ], selectedIndex: 1, version: 2, splitIndices: [2, 1])
        let restored = try JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertNil(restored.entries[0].url)
        XCTAssertEqual(restored.entries[1].favoriteID, favorite)
        XCTAssertEqual(restored.entries[2].pinned, true)
        XCTAssertEqual(restored.restoredSelectedIndex, 1)
        XCTAssertEqual(restored.restoredSplitIndices, [2, 1])
    }

    func testMalformedPaneReferencesAreBoundedAndDeduplicated() {
        var snapshot = SessionSnapshot(entries: Array(repeating: .init(url: nil, title: "Home"), count: 6),
            selectedIndex: 99, splitIndices: [-1, 2, 2, 99, 0, 1, 3, 4, 5])
        XCTAssertEqual(snapshot.restoredSelectedIndex, 5)
        XCTAssertEqual(snapshot.restoredSplitIndices, [2, 0, 1, 3])
        snapshot.selectedIndex = -9
        snapshot.splitIndices = [2, 2, 99]
        XCTAssertEqual(snapshot.restoredSelectedIndex, 0)
        XCTAssertEqual(snapshot.restoredSplitIndices, [])
        snapshot.entries = []
        XCTAssertNil(snapshot.restoredSelectedIndex)
        XCTAssertEqual(snapshot.restoredSplitIndices, [])
    }
}
