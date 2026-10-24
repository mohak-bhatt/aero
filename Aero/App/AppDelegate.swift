import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        WindowCoordinator.shared.startKeyMonitor()
        WindowCoordinator.shared.openWindow(primary: true)
        if Onboarding.needed { Onboarding.show() }
        UpdateManager.shared.checkIfDue()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowCoordinator.shared.openWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowCoordinator.shared.saveSessions()
    }
}
