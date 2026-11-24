import SwiftUI
import AppKit

struct OmniboxFrameKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Address pill: page menu, centered domain (native NSTextField), reload. Used by the sidebar
/// and the horizontal toolbar.
struct OmniboxView: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var state: BrowserState
    @ObservedObject private var manager: TabManager
    var height: CGFloat
    var showsExtensions = true
    var includesPageControls = true

    @State private var editing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tab: BrowserTab, state: BrowserState, height: CGFloat, showsExtensions: Bool = true, includesPageControls: Bool = true) {
        _tab = ObservedObject(wrappedValue: tab)
        _state = ObservedObject(wrappedValue: state)
        _manager = ObservedObject(wrappedValue: state.tabs)
        self.height = height
        self.showsExtensions = showsExtensions
        self.includesPageControls = includesPageControls
    }

    var body: some View {
        HStack(spacing: 0) {
            if includesPageControls { PageMenuButton(tab: tab, state: state, manager: manager) }
            OmniboxTextField(
                displayText: tab.url?.omniboxDisplay ?? "",
                fullText: tab.url?.absoluteString ?? "",
                placeholder: "Search or enter website",
                focusRequest: Binding(get: { state.pendingOmniboxFocus }, set: { state.pendingOmniboxFocus = $0 }),
                isEditing: $editing,
                onSubmit: { state.submit($0) },
                onChange: { state.updateSuggestions($0) },
                onMove: { state.moveSuggestion(by: $0) },
                onEnd: { state.clearSuggestions() })
            if includesPageControls { Button { tab.reloadOrStop() } label: {
                Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: tab.isLoading)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RubberButtonStyle())
            .opacity(0.85)
            .help(tab.isLoading ? "Stop" : "Reload (⌘R)") }
        }
        .padding(.horizontal, 4)
        .frame(height: height)
        .glass(in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(editing ? 0.6 : 0), lineWidth: 2)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.12), value: editing)
        .anchorPreference(key: OmniboxFrameKey.self, value: .bounds) { ["omnibox": $0] }
    }
}

/// Page menu button at the leading edge of the pill; opens a compact Safari-style panel.
struct PageMenuButton: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var state: BrowserState
    @ObservedObject var manager: TabManager
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(RubberButtonStyle())
        .opacity(0.85)
        .help("Page Menu")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            PageMenuPopover(tab: tab, state: state, manager: manager, dismiss: { open = false })
        }
    }
}

// MARK: - Native text field

final class OmniboxNSTextField: NSTextField {
    var onBecomeFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onBecomeFirstResponder?() }
        return ok
    }

    /// Clicking into the field selects the whole address once the click finishes.
    override func mouseDown(with event: NSEvent) {
        let wasEditing = currentEditor() != nil
        super.mouseDown(with: event)
        if !wasEditing { currentEditor()?.selectAll(nil) }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }
}

struct OmniboxTextField: NSViewRepresentable {
    let displayText: String
    let fullText: String
    let placeholder: String
    @Binding var focusRequest: Bool
    @Binding var isEditing: Bool
    let onSubmit: (String) -> Void
    let onChange: (String) -> Void
    let onMove: (Int) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> OmniboxNSTextField {
        let field = OmniboxNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingTail
        field.placeholderString = placeholder
        field.alignment = .center
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let coordinator = context.coordinator
        coordinator.field = field
        field.onBecomeFirstResponder = { [weak coordinator] in coordinator?.beganEditing() }
        return field
    }

    func updateNSView(_ field: OmniboxNSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        let editingNow = field.currentEditor() != nil
        if !editingNow {
            if field.stringValue != displayText { field.stringValue = displayText }
            field.alignment = .center
        }
        // Keep the blue ring honest: it follows real focus.
        if isEditing != editingNow { DispatchQueue.main.async { isEditing = editingNow } }
        if focusRequest {
            DispatchQueue.main.async {
                guard let window = field.window, !field.isHiddenOrHasHiddenAncestor else { return }
                window.makeFirstResponder(field)
                field.selectText(nil)
                if field.currentEditor() != nil { focusRequest = false }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OmniboxTextField
        weak var field: OmniboxNSTextField?
        init(_ parent: OmniboxTextField) { self.parent = parent }

        func beganEditing() {
            guard let field else { return }
            field.alignment = .left
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                field.stringValue = self.parent.fullText
                field.currentEditor()?.selectAll(nil)
                self.parent.isEditing = true
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let text = (obj.object as? NSTextField)?.stringValue { parent.onChange(text) }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field else { return }
            field.alignment = .center
            field.stringValue = parent.displayText
            DispatchQueue.main.async { self.parent.isEditing = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.parent.onEnd() }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let text = textView.string
                control.window?.makeFirstResponder(nil)
                parent.onSubmit(text)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1); return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1); return true
            default:
                return false
            }
        }
    }
}
