import SwiftUI
import AppKit

enum Metrics {
    static let tabRowHeight: CGFloat = 48
    static let toolbarHeight: CGFloat = 44
    static let trafficLightInset: CGFloat = 84
    static let trafficLightLeading: CGFloat = 20
    static let sidebarWidth: CGFloat = 280
}

// MARK: - Liquid Glass

#if compiler(>=6.2)
@available(macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}
#endif

extension View {
    /// Liquid Glass on macOS 26+, a material-based approximation before that.
    @ViewBuilder
    func glass<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            glassFallback(in: shape, tint: tint)
        }
        #else
        glassFallback(in: shape, tint: tint)
        #endif
    }

    private func glassFallback<S: InsettableShape>(in shape: S, tint: Color?) -> some View {
        self
            .background {
                shape.fill(.regularMaterial)
                if let tint { shape.fill(tint.opacity(0.15)) }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }

    /// `onChange` without the macOS 14 deprecation warning.
    @ViewBuilder
    func onValueChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, new in action(new) }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

// MARK: - Window material

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Shared backdrop for the tab row and toolbar so they read as one attached surface.
struct ChromeBackground: View {
    var body: some View {
        VisualEffectView(material: .headerView)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5)
            }
    }
}

// MARK: - Controls

struct ChromeIconButton: View {
    let symbol: String
    let help: String
    var enabled: Bool = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .opacity(enabled ? 0.85 : 0.3)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(hovering && enabled ? 0.08 : 0)))
        .onHover { hovering = $0 }
        .disabled(!enabled)
        .help(help)
    }
}


// MARK: - Interactive glass controls (rubbery press, exact sizes)

/// Squashes and stretches on press, like iOS 26 glass buttons.
struct RubberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(x: configuration.isPressed ? 1.10 : 1,
                         y: configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

/// Groups nearby glass so it can merge and morph. Passthrough before macOS 26.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct GlassShapeModifier: ViewModifier {
    let isCircle: Bool

    func body(content: Content) -> some View {
        if isCircle {
            content.glass(in: Circle(), interactive: true).contentShape(Circle())
        } else {
            content.glass(in: Capsule(), interactive: true).contentShape(Capsule())
        }
    }
}

/// Liquid Glass button with an exact size: circle when width == height, capsule otherwise.
struct GlassButton<Label: View>: View {
    enum Kind { case circle, capsule }

    let kind: Kind
    let help: String
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    let label: Label

    init(_ kind: Kind = .circle,
         help: String,
         width: CGFloat,
         height: CGFloat? = nil,
         action: @escaping () -> Void,
         @ViewBuilder label: () -> Label) {
        self.kind = kind
        self.help = help
        self.width = width
        self.height = height ?? width
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(width: width, height: height)
                .modifier(GlassShapeModifier(isCircle: kind == .circle))
        }
        .buttonStyle(RubberButtonStyle())
        .help(help)
    }
}

struct GlassShareLink: View {
    let url: URL
    let diameter: CGFloat
    let iconSize: CGFloat

    var body: some View {
        ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: iconSize, weight: .medium))
                .frame(width: diameter, height: diameter)
                .modifier(GlassShapeModifier(isCircle: true))
        }
        .buttonStyle(RubberButtonStyle())
        .help("Share")
    }
}
