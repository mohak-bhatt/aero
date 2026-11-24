import AppKit
import Combine
import WebKit

@MainActor
protocol TabHost: AnyObject {
    func openInNewTab(_ url: URL, select: Bool, from tab: BrowserTab)
    func openPopup(configuration: WKWebViewConfiguration, from tab: BrowserTab) -> BrowserTab
    func closeTab(_ tab: BrowserTab)
    func tabDidFocus(_ tab: BrowserTab)
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
    @Published var pullRefreshProgress: CGFloat = 0
    @Published private(set) var audioMuted = false
    func toggleTabAudio() {
        audioMuted.toggle()
        let script = "window.__aero && window.__aero.setMuted(\(audioMuted ? "true" : "false"))"
        webView.evaluateJavaScript(script, completionHandler: nil)
        if let mediaFrame, !mediaFrame.isMainFrame { webView.evaluateJavaScript(script, in: mediaFrame, in: .page) { _ in } }
    }
    @Published var historyNavigationPulse = 0
    @Published var backPulse = 0
    @Published var forwardPulse = 0
    func activateHistoryFeedback(back: Bool) {
        if back { backPulse += 1 } else { forwardPulse += 1 }
        AeroHaptics.perform(.generic)
    }
    var historyNavigationPending = false
    func completeHistoryNavigation() {
        guard historyNavigationPending else { return }
        historyNavigationPending = false
        historyNavigationPulse += 1
    }
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
    struct NavigationFailure {
        let url: URL?
        let message: String
    }
    @Published private(set) var navigationFailure: NavigationFailure?
    private(set) var requestedURL: URL?

    func prepareNavigation(to url: URL) {
        requestedURL = url
        navigationFailure = nil
    }

    func recordNavigationFailure(_ error: Error) {
        let ns = error as NSError
        guard !(ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled),
              !(ns.domain == "WebKitErrorDomain" && ns.code == 102) else { return }
        let failing = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? requestedURL ?? url
        navigationFailure = NavigationFailure(url: failing, message: ns.localizedDescription)
        if let failing { url = failing }
        isLoading = false
    }

    var mediaFrame: WKFrameInfo?
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
        webView.allowsLinkPreview = true // Native Force Touch link and detected-data previews.
        #if DEBUG
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        #endif
        observeWebView()
        installMedia()
        installPasswords()
        (webView as? AeroWebView)?.onPullProgress = { [weak self] in self?.pullRefreshProgress = $0 }
        (webView as? AeroWebView)?.onPullRefresh = { [weak self] in self?.reload() }
        (webView as? AeroWebView)?.onShowActivity = { [weak self] in self?.showInLiveActivities() }
        (webView as? AeroWebView)?.onFocus = { [weak self] in
            guard let self else { return }
            self.host?.tabDidFocus(self)
        }
        if let url {
            if loadImmediately { load(url) } else { pendingURL = url }
        }
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        config.webExtensionController = ExtensionManager.shared.controller
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        return config
    }

    // MARK: Navigation

    func load(_ url: URL) {
        pendingURL = nil
        prepareNavigation(to: url)
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
        AeroHaptics.perform(.levelChange)
        if let failed = navigationFailure?.url { load(failed) }
        else if webView.url == nil, let url { load(url) } else { webView.reload() }
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
            controller.addUserScript(WKUserScript(source: MediaScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
    }

    // MARK: Passwords (autofill + save prompt)

    private func installPasswords() {
        let controller = webView.configuration.userContentController
        controller.removeScriptMessageHandler(forName: "aeroPass", contentWorld: PasswordScript.world)
        controller.add(PasswordMessageHandler(tab: self), contentWorld: PasswordScript.world, name: "aeroPass")
        if !controller.userScripts.contains(where: { $0.source == PasswordScript.source }) {
            controller.addUserScript(WKUserScript(source: PasswordScript.source, injectionTime: .atDocumentEnd,
                                                 forMainFrameOnly: true, in: PasswordScript.world))
        }
    }

    func handlePassword(_ message: WKScriptMessage) {
        let frame = message.frameInfo
        let origin = frame.securityOrigin
        guard let frameURL = frame.request.url,
              message.webView === webView, message.world == PasswordScript.world,
              let body = message.body as? [String: Any],
              let host = PasswordOriginPolicy.trustedHost(pageURL: webView.url,
                  frameURL: frame.request.url, isMainFrame: frame.isMainFrame,
                  originScheme: origin.protocol, originHost: origin.host, originPort: origin.port) else { return }
        let store = PasswordStore.shared
        switch body["type"] as? String {
        case "lookup":
            // Host-only legacy credentials cannot distinguish custom-port origins.
            let credentials = store.credentials(for: host)
            guard credentials.count == 1, let credential = credentials.first,
                  let password = store.password(host: credential.host, username: credential.username) else { return }
            let call = "window.__aeroPass && window.__aeroPass.fill(\(PasswordStore.js(credential.username)), \(PasswordStore.js(password)), \(PasswordStore.js(frameURL.absoluteString)))"
            webView.evaluateJavaScript(call, in: frame, in: PasswordScript.world) { _ in }
        case "submit":
            guard let password = body["password"] as? String, !password.isEmpty else { return }
            store.offerToSave(host: host, username: body["username"] as? String ?? "", password: password)
        default: break
        }
    }

    private var isClosed = false

    func showInLiveActivities() { MediaHub.shared.show(id) }

    func handleMedia(_ body: [String: Any], frame: WKFrameInfo? = nil) {
        guard !isClosed else { return }
        if let frame {
            mediaFrame = frame
            if audioMuted { webView.evaluateJavaScript("window.__aero && window.__aero.setMuted(true)", in: frame, in: .page) { _ in } }
        }
        guard let playing = body["playing"] as? Bool else { return }
        let info = MediaInfo(isPlaying: playing,
                             isVideo: body["video"] as? Bool ?? false,
                             title: (body["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? displayTitle,
                             artist: body["artist"] as? String ?? "",
                             artworkURL: (body["artwork"] as? String).flatMap(URL.init(string:)),
                             duration: Self.safeMediaTime(body["duration"] as? Double ?? 0),
                             currentTime: Self.safeMediaTime(body["time"] as? Double ?? 0),
                             isMainFrame: frame?.isMainFrame ?? true,
                             videoWidth: body["width"] as? Double ?? 0,
                             videoHeight: body["height"] as? Double ?? 0)
        MediaHub.shared.update(id, info)
    }

    static func safeMediaTime(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }

    func seekMedia(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let script = "window.__aero && window.__aero.seek(\(seconds))"
        webView.evaluateJavaScript(script, in: mediaFrame, in: .page) { _ in }
    }

    func mediaCommand(_ command: String) {
        guard ["prev", "next", "play", "pause", "toggle", "back10", "fwd10", "pip", "lift", "unlift", "mute"].contains(command) else { return }
        let script = "window.__aero && window.__aero.\(command)()"
        if let mediaFrame {
            webView.evaluateJavaScript(script, in: mediaFrame, in: .page) { _ in }
        } else {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    // MARK: Lifecycle

    func tearDown() {
        isClosed = true
        MediaHub.shared.forget(id)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "aeroPass", contentWorld: PasswordScript.world)
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
                guard let self, self.navigationFailure == nil else { return }
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
