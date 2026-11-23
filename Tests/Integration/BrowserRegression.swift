import AppKit
import WebKit

@main
struct BrowserRegression {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var failures: [String] = []
        var count = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            count += 1
            if condition() { print("PASS: \(name)") }
            else { failures.append(name); print("FAIL: \(name)") }
        }
        let testWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let nativeButtons = buttonTypes.compactMap { testWindow.standardWindowButton($0) }
        let originalParents = nativeButtons.map { $0.superview }
        let originalFrames = nativeButtons.map { $0.frame }
        let lightHost = VerticalTrafficLights.Host(frame: NSRect(x: 0, y: 0, width: 52, height: 84))
        testWindow.contentView?.addSubview(lightHost)
        lightHost.layoutSubtreeIfNeeded()
        check("traffic lights use original system buttons", nativeButtons.allSatisfy { $0.superview === lightHost })
        check("traffic lights share a column", Set(nativeButtons.map { $0.frame.midX }).count == 1)
        check("traffic lights have distinct rows", Set(nativeButtons.map { $0.frame.minY }).count == 3)
        check("traffic lights visible on attachment", nativeButtons.allSatisfy { !$0.isHidden && $0.alphaValue == 1 })
        check("traffic lights fit narrow rail", nativeButtons.allSatisfy { lightHost.bounds.contains($0.frame) })
        if let button = nativeButtons.first, let originalParent = originalParents.first ?? nil {
            button.removeFromSuperview(); originalParent.addSubview(button)
            lightHost.attach(); lightHost.layoutSubtreeIfNeeded()
            check("traffic lights reclaim system reparenting", button.superview === lightHost)
        }
        lightHost.restore()
        check("traffic lights restore native hosts", nativeButtons.indices.allSatisfy { nativeButtons[$0].superview === originalParents[$0] })
        check("traffic lights restore native frames", nativeButtons.map { $0.frame } == originalFrames)
        lightHost.removeFromSuperview()

        func icon(_ color: NSColor, transparent: Bool) -> NSImage {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for y in 0..<8 { for x in 0..<8 {
                let c = color.usingColorSpace(.sRGB)!
                var pixel = [Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255), transparent && x < 2 ? 0 : 255]
                bitmap.setPixel(&pixel, atX: x, y: y)
            } }
            let image = NSImage(size: NSSize(width: 8, height: 8)); image.addRepresentation(bitmap)
            return image
        }
        check("transparent black favicon adapts", FaviconImage.isDarkTransparentMark(icon(.black, transparent: true)))
        check("opaque favicon stays unchanged", !FaviconImage.isDarkTransparentMark(icon(.black, transparent: false)))
        check("coloured favicon stays unchanged", !FaviconImage.isDarkTransparentMark(icon(.systemRed, transparent: true)))
        check("white favicon stays unchanged", !FaviconImage.isDarkTransparentMark(icon(.white, transparent: true)))
        let domain = "Aero.Regression.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let failedTab = BrowserTab()
        let intended = URL(string: "http://127.0.0.1:18765/recovery")!
        failedTab.prepareNavigation(to: intended)
        failedTab.recordNavigationFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost))
        check("failed navigation retains intended URL", failedTab.url == intended)
        check("failed navigation retains retry destination", failedTab.navigationFailure?.url == intended)
        check("failure does not load generated HTML", failedTab.webView.url == nil)
        failedTab.prepareNavigation(to: intended)
        check("new navigation clears failure", failedTab.navigationFailure == nil)
        failedTab.recordNavigationFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        check("cancel does not display error", failedTab.navigationFailure == nil)
        failedTab.recordNavigationFailure(NSError(domain: "WebKitErrorDomain", code: 102))
        check("download conversion does not display error", failedTab.navigationFailure == nil)
        let redirected = URL(string: "https://example.org/redirected")!
        failedTab.recordNavigationFailure(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
            userInfo: [NSURLErrorFailingURLErrorKey: redirected]))
        check("failure prefers redirected URL", failedTab.navigationFailure?.url == redirected)
        failedTab.tearDown()
        let mediaTest = BrowserTab()
        mediaTest.webView.loadHTMLString("<html><body><audio id='a'></audio><video id='b' muted></video></body></html>", baseURL: URL(string: "https://example.test"))
        var mediaReady = false
        for _ in 0..<100 {
            if (try? await mediaTest.webView.evaluateJavaScript("!!window.__aero")) as? Bool == true { mediaReady = true; break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        check("media bridge installs on document", mediaReady)
        if mediaReady {
            _ = try? await mediaTest.webView.evaluateJavaScript("document.getElementById('b').muted = true; window.__aero.setMuted(true)")
            let muted = (try? await mediaTest.webView.evaluateJavaScript("Array.from(document.querySelectorAll('audio,video')).every(e => e.muted)")) as? Bool
            check("tab mute covers multiple media elements", muted == true)
            _ = try? await mediaTest.webView.evaluateJavaScript("window.__aero.setMuted(false)")
            let restoredMute = (try? await mediaTest.webView.evaluateJavaScript("!document.getElementById('a').muted && document.getElementById('b').muted")) as? Bool
            check("unmute preserves original site mute state", restoredMute == true)
        }
        mediaTest.tearDown()
        let bookmarks = BookmarkStore(defaults: defaults)
        check("download strips traversal", DownloadManager.safeFilename("../../secret.txt") == "secret.txt")
        check("download strips Windows path", DownloadManager.safeFilename("C:\\folder\\file.txt") == "file.txt")
        check("download empty fallback", DownloadManager.safeFilename("") == "Download")
        check("download dot fallback", DownloadManager.safeFilename("..") == "Download")
        check("download strips control characters", DownloadManager.safeFilename("a\n.txt") == "a.txt")
        let downloadFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: downloadFolder) }
        let existing = downloadFolder.appendingPathComponent("test.txt")
        try! Data("existing".utf8).write(to: existing)
        check("download existing file collision", DownloadManager.uniqueURL(in: downloadFolder, filename: "test.txt").lastPathComponent == "test 1.txt")
        let reserved = downloadFolder.appendingPathComponent("test 1.txt")
        check("download simultaneous collision", DownloadManager.uniqueURL(in: downloadFolder, filename: "test.txt", excluding: [reserved]).lastPathComponent == "test 2.txt")
        check("download confined to folder", DownloadManager.uniqueURL(in: downloadFolder, filename: "../../outside.txt").deletingLastPathComponent().standardizedFileURL.path == downloadFolder.standardizedFileURL.path)
        bookmarks.addFolder(title: "Folder")
        let folder = bookmarks.items[0].id
        bookmarks.addBookmark(title: "Café", url: URL(string: "https://example.com")!, icon: nil, to: folder)
        let bookmark = bookmarks.items[0].children![0]
        check("nested bookmark inserted", bookmarks.items[0].children?.count == 1)
        check("bookmark diacritic search", bookmarks.search("cafe", limit: 3).count == 1)
        check("bookmark URL search", bookmarks.search("example.com", limit: 3).count == 1)
        check("bookmark duplicate detection", bookmarks.contains(bookmark.url))
        bookmarks.move(folder, to: bookmark.id)
        check("folder cycle prevented", bookmarks.items.count == 1)
        bookmarks.move(bookmark.id, to: nil)
        check("move bookmark out of folder", bookmarks.items.count == 2)
        bookmarks.rename(bookmark.id, to: "Renamed")
        check("rename bookmark", bookmarks.items[1].title == "Renamed")
        bookmarks.addBookmark(title: "Second", url: URL(string: "https://example.org")!, icon: nil)
        let second = bookmarks.items.last!.id
        bookmarks.move(second, to: bookmark.id)
        check("cannot hide bookmark inside nonfolder", BookmarkStore.flatten(bookmarks.items).count == 2)
        check("bookmarks persist", BookmarkStore(defaults: defaults).items == bookmarks.items)
        bookmarks.delete(bookmark.id)
        check("delete bookmark", !bookmarks.contains(bookmark.url))

        let history = HistoryStore(defaults: defaults)
        let url = URL(string: "https://example.com")!
        history.record(url: url, title: "First")
        history.record(url: url, title: "Second")
        check("repeat visit increments", history.entries.count == 1 && history.entries[0].visits == 2)
        check("history title updated", history.entries[0].title == "Second")
        history.record(url: URL(fileURLWithPath: "/tmp/secret"), title: "Private")
        check("file excluded from history", history.entries.count == 1)
        let imported = HistoryEntry(url: URL(string: "https://example.org")!, title: "Imported", visits: 1, lastVisit: Date())
        history.importEntries([imported, imported])
        check("import batch deduplicated", history.entries.count == 2)
        history.importEntries([HistoryEntry(url: URL(string: "javascript:alert(1)")!, title: "Unsafe", visits: 1, lastVisit: Date())])
        check("nonweb history import rejected", history.entries.count == 2)
        check("history persistence", HistoryStore(defaults: defaults).entries.count == history.entries.count)
        history.clear()
        check("history clear persisted", HistoryStore(defaults: defaults).entries.isEmpty)

        for (input, expected) in [("example.com", "https://example.com"), ("localhost:8080", "http://localhost:8080"), ("127.0.0.1:8080", "http://127.0.0.1:8080"), (" https://example.com/a ", "https://example.com/a"), ("about:blank", "about:blank")] {
            check("resolve \(input)", URLResolver.resolve(input)?.absoluteString == expected)
        }
        check("empty address ignored", URLResolver.resolve("  \n") == nil)
        check("search preserves query", URLComponents(url: URLResolver.resolve("a & b # c")!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "a & b # c")
        check("CSV quoted commas", PasswordStore.parseCSV("name,password\n\"a,b\",\"c\"\"d\"\n") == [["name","password"],["a,b","c\"d"]])
        check("CSV CRLF", PasswordStore.parseCSV("a,b\r\nc,d\r\n").count == 2)
        check("CSV embedded newline", PasswordStore.parseCSV("a,\"b\nc\"")[0][1] == "b\nc")
        check("JS string quoting", PasswordStore.js("\"\\\n").hasPrefix("\""))

        let layouts = BrowserLayoutStore(defaults: defaults)
        check("layout absent allows legacy preferences", layouts.load() == nil)
        for preset in BrowserLayout.Preset.allCases {
            let layout = BrowserLayout.configuration(for: preset)
            layouts.save(layout)
            check("layout round trip \(preset.rawValue)", layouts.load() == layout.validated())
        }
        check("shipping presets exclude horizontal", !BrowserLayout.Preset.shippingCases.contains(where: { $0.isHorizontal }))
        check("saved horizontal falls back to vertical", BrowserLayout.configuration(for: .horizontal).validated().preset == .classic)
        check("focus hides pinned sidebar", !BrowserLayout.configuration(for: .focus).sidebarPinned)
        check("classic keeps sidebar", BrowserLayout.configuration(for: .classic).sidebarPinned)
        check("sidebar stays expanded at minimum", !BrowserLayout.shouldCollapse(proposedWidth: 264, minimumWidth: 264))
        check("sidebar tolerates slight overshoot", !BrowserLayout.shouldCollapse(proposedWidth: 250, minimumWidth: 264))
        check("sidebar collapses beyond threshold", BrowserLayout.shouldCollapse(proposedWidth: 247, minimumWidth: 264))
        check("invalid resize cannot collapse", !BrowserLayout.shouldCollapse(proposedWidth: -.infinity, minimumWidth: 264))
        check("compact stays visible", BrowserLayout.configuration(for: .compact).sidebarPinned)
        let legacyLayout = Data(#"{"version":1,"preset":"classic","sidebarWidth":310,"sidebarPinned":false}"#.utf8)
        check("legacy layout remains readable", (try? JSONDecoder().decode(BrowserLayout.self, from: legacyLayout))?.sidebarWidth == 310)

        check("layout width lower bound", BrowserLayout(sidebarWidth: -10).validated().sidebarWidth == 200)
        check("layout width upper bound", BrowserLayout(sidebarWidth: 9999).validated().sidebarWidth == 420)
        check("layout nonfinite fallback", BrowserLayout(sidebarWidth: .infinity).validated().sidebarWidth == 270)
        check("unknown layout version fallback", BrowserLayout(version: 99).validated() == BrowserLayout())
        let tabs = TabManager()
        let first = tabs.newTab()
        let secondTab = tabs.newTab()
        check("new tab selected", tabs.selectedID == secondTab.id)
        tabs.selectPrevious()
        check("previous tab", tabs.selectedID == first.id)
        tabs.selectPrevious()
        check("previous wraps", tabs.selectedID == secondTab.id)
        tabs.togglePin(first)
        check("pin separates normal tabs", tabs.pinnedTabs.count == 1 && tabs.unpinnedTabs.count == 1)
        let favourite = Favorite(url: URL(string: "https://example.test")!, title: "Split favourite")
        tabs.registerFavoriteTab(secondTab, for: favourite)
        tabs.split(first, with: secondTab)
        check("favourite and pinned tab can split", tabs.splitIDs.contains(first.id) && tabs.splitIDs.contains(secondTab.id))
        tabs.releaseFavorite(id: favourite.id)
        tabs.split(first, with: secondTab)
        check("split has two panes", tabs.selectedSplit?.count == 2)
        let third = tabs.newTab(); let fourth = tabs.newTab(); let fifth = tabs.newTab()
        tabs.split(third, with: first); tabs.split(fourth, with: first); tabs.split(fifth, with: first)
        check("split maximum four", tabs.splitIDs.count == 4)
        tabs.selectTab(first)
        tabs.splitStacked = true
        let originalOrder = tabs.splitIDs
        tabs.moveSplitPane(first, by: 1)
        check("split pane moves", tabs.splitIDs != originalOrder)
        tabs.moveSplitPane(first, by: -1)
        check("split pane move reverses", tabs.splitIDs == originalOrder)
        tabs.moveSplitPane(first, by: -99)
        check("split movement bounds checked", tabs.splitIDs == originalOrder)
        let saved = tabs.snapshot()
        let restored = TabManager(); restored.restore(saved)
        check("split orientation restores", restored.splitStacked)
        check("restore home tabs", restored.tabs.count == 5)
        check("restore selected pane", restored.selectedID == restored.tabs[0].id)
        check("restore split order", restored.splitIDs == saved.restoredSplitIndices.map { restored.tabs[$0].id })
        restored.restore(saved)
        check("restore cannot duplicate populated manager", restored.tabs.count == 5)
        tabs.removeFromSplit(first); tabs.removeFromSplit(secondTab); tabs.removeFromSplit(third)
        check("single pane collapses split", tabs.splitIDs.isEmpty)
        let moved = tabs.detach(secondTab)!
        let destination = TabManager(); destination.adopt(moved)
        check("detach preserves identity", destination.tabs[0] === secondTab && !tabs.tabs.contains { $0 === secondTab })
        let restoredFocus = restored.tabs[0]
        restored.focusOnly(restoredFocus)
        check("focus pane exits split", restored.splitIDs.isEmpty && restored.selectedID == restoredFocus.id)
        check("focus pane preserves other tabs", restored.tabs.count == 5)
        tabs.closeAll()
        check("close all retains usable home", tabs.tabs.count == 1 && tabs.selectedTab != nil)
        for manager in [tabs, restored, destination] { for tab in manager.tabs { tab.tearDown() } }
        let windows = ApplicationSessionStore(defaults: defaults)
        check("multiwindow missing archive", windows.load() == nil)
        windows.save([saved, SessionSnapshot(entries: [.init(url: nil, title: "Home")], selectedIndex: 0)])
        check("multiwindow count roundtrip", windows.load()?.count == 2)
        check("multiwindow split roundtrip", windows.load()?.first?.restoredSplitIndices == saved.restoredSplitIndices)
        check("multiwindow Home roundtrip", windows.load()?.last?.entries.first?.url == nil)
        windows.save([])
        check("multiwindow empty replaces stale archive", windows.load()?.isEmpty == true)
        let recoveryURL = downloadFolder.appendingPathComponent("Recovery/windows.json")
        let disk = ApplicationSessionStore(defaults: defaults, fileURL: recoveryURL)
        var framed = saved
        framed.windowFrame = "{{20, 40}, {900, 700}}"
        framed.wasActiveWindow = true
        disk.save([framed])
        check("atomic recovery file created", FileManager.default.fileExists(atPath: recoveryURL.path))
        check("recovery window metadata roundtrip", disk.load()?.first?.windowFrame == framed.windowFrame && disk.load()?.first?.wasActiveWindow == true)
        disk.save([framed, saved])
        try! Data("interrupted or corrupt".utf8).write(to: recoveryURL)
        check("corrupt recovery uses valid backup", disk.load()?.count == 1)
        disk.save([saved, saved, saved])
        try! Data("corrupt again".utf8).write(to: recoveryURL)
        check("corrupt primary never replaces valid backup", disk.load()?.count == 1)
        check("media infinite time sanitized", BrowserTab.safeMediaTime(.infinity) == 0)
        check("media NaN sanitized", BrowserTab.safeMediaTime(.nan) == 0)
        check("media negative time sanitized", BrowserTab.safeMediaTime(-5) == 0)
        let hub = MediaHub()
        let mediaA = UUID(), mediaB = UUID()
        var info = MediaInfo(isPlaying: true, isVideo: false, title: "Track", artist: "Test", duration: 100, currentTime: 1)
        hub.update(mediaA, info); hub.update(mediaB, info)
        info.currentTime = 10; hub.update(mediaA, info)
        check("media ticks do not steal player priority", hub.order.first == mediaB)
        info.isPlaying = false; hub.update(mediaA, info)
        info.isPlaying = true; hub.update(mediaA, info)
        check("pause and resume preserve card order to avoid flicker", hub.order == [mediaB, mediaA])
        hub.update(mediaA, nil)
        check("closed media source removed", !hub.order.contains(mediaA) && hub.items[mediaA] == nil)
        info.videoWidth = 1920; info.videoHeight = 800
        check("cinema video keeps intrinsic ratio", info.videoAspectRatio == 2.4)
        info.videoWidth = 1080; info.videoHeight = 1920
        check("portrait video keeps intrinsic ratio", info.videoAspectRatio == 0.5625)
        info.videoWidth = 600; info.videoHeight = 600
        check("square video keeps intrinsic ratio", info.videoAspectRatio == 1)
        for dimensions: (Double, Double) in [(0, 0), (.nan, 10), (10, .infinity), (-1, 1), (.leastNonzeroMagnitude, .greatestFiniteMagnitude)] {
            info.videoWidth = dimensions.0; info.videoHeight = dimensions.1
            check("invalid video dimensions fall back safely", info.videoAspectRatio == 16.0 / 9.0)
        }
        let activities = LiveActivitiesStore()
        var activity = LiveActivity(id: UUID(), kind: .assistantTask, title: "Test", detail: "Working")
        activities.upsert(activity)
        activity.progress = 1.5; activity.status = .completed
        activities.upsert(activity)
        check("activity updates preserve identity without duplication", activities.activities.count == 1 && activities.activities[0].status == .completed)
        check("activity progress clamps upper bound", activity.normalizedProgress == 1)
        activity.progress = -1
        check("activity progress clamps lower bound", activity.normalizedProgress == 0)
        activity.progress = .nan
        check("invalid activity progress is indeterminate", activity.normalizedProgress == nil)
        activities.remove(activity.id)
        check("activity removal clears state", activities.activities.isEmpty)
        let epoch = Date(timeIntervalSince1970: 1000)
        let timerID = UUID()
        activities.upsert(LiveActivity(id: timerID, kind: .timer, title: "Test timer", detail: "", deadline: epoch.addingTimeInterval(60)))
        activities.toggleTimer(timerID, now: epoch.addingTimeInterval(20))
        check("timer pause preserves remaining time", activities.activities.first?.pausedRemaining == 40 && activities.activities.first?.deadline == nil)
        activities.advance(to: epoch.addingTimeInterval(200))
        check("paused timer does not expire", activities.activities.first?.status == .paused)
        activities.toggleTimer(timerID, now: epoch.addingTimeInterval(200))
        check("timer resume uses remaining time", activities.activities.first?.deadline == epoch.addingTimeInterval(240))
        activities.toggleTimer(timerID, now: epoch.addingTimeInterval(240))
        check("pause at expiry completes timer", activities.activities.first?.status == .completed)
        activities.toggleTimer(timerID, now: epoch.addingTimeInterval(250))
        check("completed timer cannot resume", activities.activities.first?.status == .completed && activities.activities.first?.deadline == nil)
        activities.remove(timerID)
        for invalid in [Double.nan, Double.infinity, -1, 0, 86401] { activities.startTimer(seconds: invalid) }
        check("invalid timer durations rejected", activities.activities.isEmpty)
        activities.addClock(); activities.addClock()
        check("local clock is not duplicated", activities.activities.count == 1)
        activities.remove(activities.activities[0].id)
        let activityID = UUID()
        let instagram = URL(string: "https://www.instagram.com/reels/")!
        check("Instagram activity requires opt in", !hub.permits(activityID, url: instagram))
        hub.show(activityID)
        check("Instagram explicit opt in allowed", hub.permits(activityID, url: instagram))
        hub.dismiss(activityID)
        hub.update(activityID, info)
        check("media ticks cannot undo dismissal", !hub.permits(activityID, url: instagram))
        hub.show(activityID)
        check("explicit show restores dismissed activity", hub.permits(activityID, url: instagram))
        hub.forget(activityID)
        check("forget removes activity and presentation state", hub.items[activityID] == nil && !hub.explicit.contains(activityID) && !hub.dismissed.contains(activityID))
        let closedMedia = BrowserTab()
        closedMedia.tearDown()
        closedMedia.handleMedia(["playing": true, "title": "Late event"])
        check("closed tab rejects queued media messages", MediaHub.shared.items[closedMedia.id] == nil)
        print("RESULT: \(count) checks, \(failures.count) failures")
        exit(failures.isEmpty ? 0 : 1)
    }
}
