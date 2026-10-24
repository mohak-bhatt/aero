import AppKit
import WebKit

// MARK: - Navigation

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }

        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            let flags = navigationAction.modifierFlags
            if flags.contains(.option) { return .download }
            // ⌘-click or middle-click opens a tab; adding ⇧ brings it to the front.
            if flags.contains(.command) || navigationAction.buttonNumber == 4 {
                host?.openInNewTab(url, select: flags.contains(.shift), from: self)
                return .cancel
            }
        }
        return .allow
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView.url?.host != faviconHost { favicon = nil }
        applySavedZoom()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadFavicon()
        updateThemeColor()
        if let url = webView.url { HistoryStore.shared.record(url: url, title: webView.title ?? "") }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: Favicon

    private func loadFavicon() {
        guard let pageURL = webView.url, pageURL.scheme?.hasPrefix("http") == true else { return }
        let script = """
        (() => {
          const links = [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')];
          return links.length ? links[0].href : '';
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            var iconURL: URL?
            if let string = result as? String, !string.isEmpty { iconURL = URL(string: string) }
            if iconURL == nil, let host = pageURL.host {
                iconURL = URL(string: "\(pageURL.scheme ?? "https")://\(host)/favicon.ico")
            }
            guard let iconURL else { return }
            Task { @MainActor in
                guard let (data, _) = try? await URLSession.shared.data(from: iconURL),
                      let image = NSImage(data: data) else { return }
                self.favicon = image
                self.faviconHost = pageURL.host
            }
        }
    }

    // MARK: Theme colour

    private func updateThemeColor(retry: Bool = true) {
        let script = """
        (() => {
          const ok = c => (c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') ? c : null;
          const meta = document.querySelector('meta[name="theme-color"]');
          if (meta && ok(meta.content)) return meta.content;
          let el = document.elementFromPoint(Math.floor(innerWidth / 2), 4);
          while (el) {
            const c = ok(getComputedStyle(el).backgroundColor);
            if (c) return c;
            el = el.parentElement;
          }
          return ok(getComputedStyle(document.body).backgroundColor)
            || ok(getComputedStyle(document.documentElement).backgroundColor)
            || '';
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }
            Task { @MainActor in
                let parsed = (result as? String).flatMap(Self.parseCSSColor)
                // White / near-white or unparseable pages get no tint at all.
                self.themeColor = parsed.flatMap { Self.isNearlyWhite($0) ? nil : $0 }
            }
        }
        if retry {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.updateThemeColor(retry: false)
            }
        }
    }

    private static func isNearlyWhite(_ color: NSColor) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return true }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.85
    }

    private static func parseCSSColor(_ string: String) -> NSColor? {
        let text = string.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 8 { hex = String(hex.prefix(6)) }
            guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255,
                           alpha: 1)
        }
        guard text.hasPrefix("rgb"),
              let open = text.firstIndex(of: "("),
              let close = text.firstIndex(of: ")") else { return nil }
        let parts = text[text.index(after: open)..<close]
            .split(whereSeparator: { ",/ ".contains($0) })
            .compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        if parts.count > 3, parts[3] < 0.05 { return nil }
        return NSColor(srgbRed: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: 1)
    }

    // MARK: Error page

    private func showError(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // converted to download
        let failing = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        let message = Self.escape(ns.localizedDescription)
        let address = Self.escape(failing?.absoluteString ?? "")
        let html = """
        <!doctype html><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>
          body { font: 15px -apple-system, system-ui; display: flex; height: 100vh; margin: 0;
                 align-items: center; justify-content: center; text-align: center; }
          h1 { font-size: 20px; font-weight: 600; margin: 0 0 8px; }
          p { opacity: .65; margin: 4px 0; max-width: 460px; }
        </style>
        <div><h1>Can’t open this page</h1><p>\(message)</p><p>\(address)</p></div>
        """
        webView.loadHTMLString(html, baseURL: failing)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - UI (new windows, panels)

extension BrowserTab: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        host?.openPopup(configuration: configuration, from: self).webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        host?.closeTab(self)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Aero"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "Aero"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        let response = await panel.begin()
        return response == .OK ? panel.urls : nil
    }
}

// MARK: - Downloads

extension BrowserTab: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let manager = DownloadManager.shared
        guard let destination = await manager.chooseDestination(filename: suggestedFilename) else {
            return nil // user cancelled the save panel
        }
        manager.begin(destination: destination, download: download)
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        DownloadManager.shared.finish(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        DownloadManager.shared.fail(download, error: error)
    }
}
