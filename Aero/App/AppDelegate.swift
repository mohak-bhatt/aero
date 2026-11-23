import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        WindowCoordinator.shared.startKeyMonitor()
        WindowCoordinator.shared.restoreWindows()
        if Onboarding.needed { Onboarding.show() }
        UpdateManager.shared.checkIfDue()
        WhatsNewWindow.showIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let state = WindowCoordinator.shared.activeState ?? WindowCoordinator.shared.openWindow().state
        for url in urls { state.tabs.newTab(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WindowCoordinator.shared.prepareToTerminate()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowCoordinator.shared.openWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowCoordinator.shared.saveSessions()
    }
}
