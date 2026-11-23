import AppKit

/// Tracks every browser window so menu commands act on the active one, tabs can be torn off
/// into new windows, and Ctrl+Tab can show a tab switcher.
@MainActor
final class WindowCoordinator {
    static let shared = WindowCoordinator()
    private(set) var controllers: [BrowserWindowController] = []
    private var monitor: Any?
    private var isTerminating = false
    private var isRestoring = false

    func prepareToTerminate() {
        saveSessions()
        isTerminating = true
    }

    var activeState: BrowserState? {
        if let controller = NSApp.keyWindow?.windowController as? BrowserWindowController { return controller.state }
        return controllers.last?.state
    }

    @discardableResult
    func openWindow(primary: Bool = false, adopting tab: BrowserTab? = nil, near point: NSPoint? = nil, restoredSession: SessionSnapshot? = nil) -> BrowserWindowController {
        let state = BrowserState(initialTab: tab, isPrimary: primary, restoredSession: restoredSession)
        let controller = BrowserWindowController(state: state, isPrimary: primary)
        controllers.append(controller)
        if let window = controller.window {
            if let point {
                window.setFrameTopLeftPoint(NSPoint(x: point.x - 90, y: point.y + 24))
            } else if !primary, let key = NSApp.keyWindow {
                window.setFrameTopLeftPoint(NSPoint(x: key.frame.minX + 28, y: key.frame.maxY - 28))
            }
        }
        if let value = restoredSession?.windowFrame, let window = controller.window {
            let frame = NSRectFromString(value)
            if frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
               frame.width >= 640, frame.height >= 400,
               NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                window.setFrame(frame, display: false)
            }
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    func restoreWindows() {
        isRestoring = true
        defer { isRestoring = false; saveSessions() }
        if let sessions = ApplicationSessionStore().load(), !sessions.isEmpty {
            for (index, session) in sessions.enumerated() {
                openWindow(primary: index == 0, restoredSession: session)
            }
            if let active = sessions.firstIndex(where: { $0.wasActiveWindow == true }), controllers.indices.contains(active) {
                controllers[active].window?.makeKeyAndOrderFront(nil)
            }
        } else { openWindow(primary: true) }
    }

    func remove(_ controller: BrowserWindowController) {
        controllers.removeAll { $0 === controller }
        // Closing the final window quits Aero; preserve it for the next launch.
        if !controllers.isEmpty { saveSessions() }
    }

    func saveSessions() {
        guard !isTerminating, !isRestoring, !controllers.isEmpty else { return }
        ApplicationSessionStore().save(controllers.map { controller in
            var snapshot = controller.state.tabs.snapshot()
            snapshot.windowFrame = controller.window.map { NSStringFromRect($0.frame) }
            snapshot.wasActiveWindow = controller.window?.isKeyWindow == true
            return snapshot
        })
    }

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
