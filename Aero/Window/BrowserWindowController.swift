import AppKit
import Combine
import SwiftUI

/// Owns one NSWindow. A real (empty) NSToolbar gives the native title-bar height and traffic-light
/// inset; the controller only measures it, fades the lights with the sidebar, and drops the toolbar
/// in full screen so our own chrome is the only bar.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let state: BrowserState
    private var savedToolbar: NSToolbar?
    private var cancellables = Set<AnyCancellable>()

    init(state: BrowserState, isPrimary: Bool) {
        self.state = state

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: isPrimary ? 1280 : 1100, height: isPrimary ? 820 : 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "AeroToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 640, height: 400)
        window.collectionBehavior.insert(.fullScreenPrimary)

        let hosting = NSHostingView(rootView: WindowView(state: state))
        if #available(macOS 13.0, *) { hosting.sceneBridgingOptions = [] }
        window.contentView = hosting

        super.init(window: window)
        window.delegate = self
        state.window = window

        if isPrimary {
            if !window.setFrameUsingName("AeroMainWindow") { window.center() }
            window.setFrameAutosaveName("AeroMainWindow")
        } else {
            window.center()
        }

        // Traffic lights ride along with the sidebar: hidden when it is hidden.
        Publishers.CombineLatest4(state.$layout, state.$sidebarVisible, state.$sidebarPeeking, state.$isFullScreen)
            .sink { [weak self] layout, visible, peeking, fullScreen in
                self?.setLights(visible: layout == .horizontal || visible || peeking, fullScreen: fullScreen)
            }
            .store(in: &cancellables)
        DispatchQueue.main.async { [weak self] in self?.updateMetrics() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Native metrics

    private func updateMetrics() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let height = window.frame.height - window.contentLayoutRect.height
        if height > 20 { state.titlebarHeight = height }
        if let mini = window.standardWindowButton(.miniaturizeButton),
           let zoom = window.standardWindowButton(.zoomButton), let host = zoom.superview {
            let z = host.convert(zoom.frame, to: nil)
            let m = host.convert(mini.frame, to: nil)
            if z.maxX > 40 {
                state.trafficLightsTrailing = z.maxX
                state.trafficLightGap = max(4, z.minX - m.maxX)
            }
        }
    }

    private func setLights(visible: Bool, fullScreen: Bool) {
        guard let window, !fullScreen else { return }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            if visible { button.isHidden = false }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                button.animator().alphaValue = visible ? 1 : 0
            }, completionHandler: { if !visible { button.isHidden = true } })
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) { updateMetrics() }
    func windowDidBecomeKey(_ notification: Notification) { updateMetrics() }

    func windowWillEnterFullScreen(_ notification: Notification) {
        state.isFullScreen = true
        savedToolbar = window?.toolbar
        window?.toolbar = nil          // no grey system bar: our chrome is the top bar
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.toolbar = savedToolbar
        state.isFullScreen = false
        updateMetrics()
        setLights(visible: state.layout == .horizontal || state.sidebarVisible || state.sidebarPeeking, fullScreen: false)
    }

    func windowWillClose(_ notification: Notification) {
        state.saveSession()
        WindowCoordinator.shared.remove(self)
    }
}
