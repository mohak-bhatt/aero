import AppKit
import Combine
import WebKit

@MainActor
protocol TabHost: AnyObject {
    func openInNewTab(_ url: URL, select: Bool, from tab: BrowserTab)
    func openPopup(configuration: WKWebViewConfiguration, from tab: BrowserTab) -> BrowserTab
    func closeTab(_ tab: BrowserTab)
}

/// One tab = one WKWebView. The tab is the source of truth for its own
/// title, URL, loading and navigation state (mirrored from WebKit via KVO).
@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    weak var host: TabHost?

    @Published private(set) var title: String = ""
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var zoom: CGFloat = 1
    @Published var favicon: NSImage?
    /// Page colour (theme-color meta or body background) used to tint the sidebar.
    @Published var themeColor: NSColor?
    /// Last on-screen look of this tab, used by the Ctrl+Tab switcher.
    @Published var snapshot: NSImage?

    /// Set for session-restored tabs that haven't been loaded yet.
    private(set) var pendingURL: URL?
    var faviconHost: String?
    var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var cancellables = Set<AnyCancellable>()

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.host ?? "Home"
    }

    init(url: URL? = nil,
         title: String = "",
         configuration: WKWebViewConfiguration? = nil,
         loadImmediately: Bool = true) {
        webView = AeroWebView(frame: .zero, configuration: configuration ?? BrowserTab.makeConfiguration())
        super.init()
        self.title = title
        self.url = url
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = false   // system preview was logged-out and offered Safari
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        observeWebView()
        installMedia()
        if let url {
            if loadImmediately { load(url) } else { pendingURL = url }
        }
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        return config
    }

    // MARK: Navigation

    func load(_ url: URL) {
        pendingURL = nil
        self.url = url
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// Loads a session-restored page the first time its tab becomes active.
    func activate() {
        if let pending = pendingURL { load(pending) }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reload() {
        if webView.url == nil, let url { load(url) } else { webView.reload() }
    }

    func stop() { webView.stopLoading() }

    func reloadOrStop() { isLoading ? stop() : reload() }

    // MARK: Zoom

    func zoomIn() { setZoom(webView.pageZoom + 0.1) }
    func zoomOut() { setZoom(webView.pageZoom - 0.1) }
    func resetZoom() { setZoom(1) }

    private func setZoom(_ value: CGFloat) {
        let clamped = min(max(value, 0.3), 5)
        webView.pageZoom = clamped
        zoom = clamped
        if Pref.bool(Pref.rememberZoomKey, default: true) {
            SiteZoomStore.shared.set(Double(clamped), for: webView.url?.host ?? url?.host)
        }
    }

    /// Restores this site's remembered zoom (or the default zoom) after navigation.
    func applySavedZoom() {
        let store = SiteZoomStore.shared
        let value = CGFloat(Pref.bool(Pref.rememberZoomKey, default: true)
                            ? store.zoom(for: webView.url?.host) : store.defaultZoom)
        webView.pageZoom = value
        zoom = value
    }

    /// Only snapshots web views that are actually on screen with a real size; asking WebKit to
    /// snapshot a detached or zero-sized view aborts the process.
    func captureSnapshot() {
        guard webView.window != nil, webView.bounds.width > 40, webView.bounds.height > 40 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            Task { @MainActor in if let image { self?.snapshot = image } }
        }
    }

    // MARK: Media (mini-player)

    private func installMedia() {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "aeroMedia")
        controller.add(MediaMessageHandler(tab: self), name: "aeroMedia")
        if !controller.userScripts.contains(where: { $0.source.contains("__aero") }) {
            controller.addUserScript(WKUserScript(source: MediaScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }

    func handleMedia(_ body: [String: Any]) {
        guard let playing = body["playing"] as? Bool else { return }
        let info = MediaInfo(isPlaying: playing,
                             isVideo: body["video"] as? Bool ?? false,
                             title: (body["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? displayTitle,
                             artist: body["artist"] as? String ?? "",
                             artworkURL: (body["artwork"] as? String).flatMap(URL.init(string:)),
                             duration: body["duration"] as? Double ?? 0,
                             currentTime: body["time"] as? Double ?? 0)
        MediaHub.shared.update(id, info)
    }

    func mediaCommand(_ command: String) {
        webView.evaluateJavaScript("window.__aero && window.__aero.\(command)()", completionHandler: nil)
    }

    // MARK: Lifecycle

    func tearDown() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "aeroMedia")
        MediaHub.shared.update(id, nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        cancellables.removeAll()
    }

    // MARK: KVO mirroring

    private func observeWebView() {
        webView.publisher(for: \.title)
            .sink { [weak self] value in
                if let value, !value.isEmpty { self?.title = value }
            }
            .store(in: &cancellables)

        webView.publisher(for: \.url)
            .sink { [weak self] value in
                guard let self else { return }
                if let value {
                    self.url = value
                } else if self.pendingURL == nil, !self.webView.isLoading {
                    self.url = nil
                }
            }
            .store(in: &cancellables)

        webView.publisher(for: \.isLoading)
            .sink { [weak self] in self?.isLoading = $0 }
            .store(in: &cancellables)

        webView.publisher(for: \.estimatedProgress)
            .sink { [weak self] in self?.progress = $0 }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoBack)
            .sink { [weak self] in self?.canGoBack = $0 }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoForward)
            .sink { [weak self] in self?.canGoForward = $0 }
            .store(in: &cancellables)
    }
}
