import WebKit

/// WKWebView whose right-click menu talks about tabs instead of windows.
final class AeroWebView: WKWebView {
    /// Called when the user clicks into this page (used to pick the active pane in split view).
    var onShowActivity: (() -> Void)?
    @objc private func showActivity() { onShowActivity?() }
    var onFocus: (() -> Void)?
    var onPullProgress: ((CGFloat) -> Void)?
    var onPullRefresh: (() -> Void)?
    private var pullID: UUID?
    private var pullDistance: CGFloat = 0
    private var pullAllowed = false
    private var pullArmed = false
    private var lastHorizontalGesture: TimeInterval = 0
    var historyGesturePending = false
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && event.momentumPhase.isEmpty {
            if event.phase == .began {
                let id = UUID(); pullID = id; pullDistance = 0; pullAllowed = false; pullArmed = false
                let point = convert(event.locationInWindow, from: nil)
                let y = isFlipped ? point.y : bounds.height - point.y
                let script = """
                (() => {
                    const root = document.scrollingElement;
                    if (!root || root.scrollTop > 1) return false;
                    let el = document.elementFromPoint(\(point.x), \(y));
                    while (el && el !== document.body && el !== root) {
                        const style = getComputedStyle(el);
                        if (el.scrollHeight > el.clientHeight + 1 && /auto|scroll/.test(style.overflowY)) return false;
                        el = el.parentElement;
                    }
                    return true;
                })()
                """
                evaluateJavaScript(script) { [weak self] result, _ in
                    guard let self, self.pullID == id else { return }
                    self.pullAllowed = result as? Bool == true
                }
            }
            if event.phase == .ended || event.phase == .cancelled {
                let refresh = event.phase == .ended && pullAllowed && pullArmed && pullDistance >= 100
                pullID = nil; pullAllowed = false; pullArmed = false; pullDistance = 0
                onPullProgress?(0)
                if refresh { onPullRefresh?() }
            } else if pullID != nil {
                if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                    pullAllowed = false; pullID = nil; onPullProgress?(0)
                } else if pullAllowed {
                    pullDistance = max(0, min(140, pullDistance + event.scrollingDeltaY))
                    let armed = pullDistance >= 100
                    if armed && !pullArmed { AeroHaptics.perform(.alignment) }
                    pullArmed = armed
                    onPullProgress?(min(1, pullDistance / 100))
                }
            }
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) && abs(event.scrollingDeltaX) > 2 {
                lastHorizontalGesture = ProcessInfo.processInfo.systemUptime
            }
        }
        super.scrollWheel(with: event)
    }
    func markHistoryNavigation() {
        historyGesturePending = ProcessInfo.processInfo.systemUptime - lastHorizontalGesture < 1
    }
    func finishHistoryGesture() {
        guard historyGesturePending else { return }
        historyGesturePending = false

    }

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        super.mouseDown(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        menu.addItem(.separator())
        let activity = NSMenuItem(title: "Show in Live Activities", action: #selector(showActivity), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)
        for item in menu.items where item.title.contains("Window") {
            item.title = item.title.replacingOccurrences(of: "Window", with: "Tab")
        }
    }
}
