import SwiftUI
import WebKit

/// Hosts a tab's existing WKWebView. The view is never recreated on SwiftUI
/// updates, so page, scroll and history state survive tab switches.
struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
