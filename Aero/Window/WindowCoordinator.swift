import AppKit

/// Tracks every browser window so menu commands act on the active one, tabs can be torn off
/// into new windows, and Ctrl+Tab can show a tab switcher.
@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()
    private(set) var controllers: [BrowserWindowController] = []
    private var monitor: Any?

    var activeState: BrowserState? {
        if let controller = NSApp.keyWindow?.windowController as? BrowserWindowController { return controller.state }
        return controllers.last?.state
    }

    @discardableResult
    func openWindow(primary: Bool = false, adopting tab: BrowserTab? = nil, near point: NSPoint? = nil) -> BrowserWindowController {
        let state = BrowserState(initialTab: tab, isPrimary: primary)
        let controller = BrowserWindowController(state: state, isPrimary: primary)
        controllers.append(controller)
        if let window = controller.window {
            if let point {
                window.setFrameTopLeftPoint(NSPoint(x: point.x - 90, y: point.y + 24))
            } else if !primary, let key = NSApp.keyWindow {
                window.setFrameTopLeftPoint(NSPoint(x: key.frame.minX + 28, y: key.frame.maxY - 28))
            }
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    func remove(_ controller: BrowserWindowController) { controllers.removeAll { $0 === controller } }
    func saveSessions() { controllers.forEach { $0.state.saveSession() } }

    func mergeAll(into state: BrowserState) {
        for controller in controllers where controller.state !== state {
            for tab in controller.state.tabs.tabs {
                if let moved = controller.state.tabs.detach(tab) { state.tabs.adopt(moved) }
            }
            controller.window?.close()
        }
    }

    /// Ctrl+Tab / Ctrl+Shift+Tab: most-recently-used tab switching; hold Control for previews.
    func startKeyMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let state = self?.activeState else { return event }
            let flags = event.modifierFlags
            if event.type == .keyDown, event.keyCode == 48, flags.contains(.control), !flags.contains(.command) {
                state.switcherAdvance(backwards: flags.contains(.shift))
                return nil
            }
            if event.type == .keyDown, event.keyCode == 53, state.switcherActive {
                state.switcherCommit(select: false)
                return nil
            }
            if event.type == .flagsChanged, !flags.contains(.control), state.switcherActive {
                state.switcherCommit()
            }
            return event
        }
    }
}
