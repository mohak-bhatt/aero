import SwiftUI

/// Favicon, spinner while loading, or a placeholder glyph. Shared by all tab layouts.
struct TabFavicon: View {
    @ObservedObject var tab: BrowserTab
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let image = tab.favicon {
                FaviconImage(image: image)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Image(systemName: tab.url == nil ? "house" : "globe")
                    .font(.system(size: size * 0.75))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(tab.isLoading ? 0.76 : 1)
        .overlay {
            if tab.isLoading {
                Circle().trim(from: 0, to: max(0.08, min(1, tab.progress)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: size + 3, height: size + 3)
                    .accessibilityLabel("Loading page")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: tab.isLoading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: tab.progress)
    }
}

/// Invert only near-black monochrome marks with transparency; retain their alpha mask.
struct FaviconImage: View {
    let image: NSImage
    @Environment(\.colorScheme) private var colorScheme
    @State private var darkMark = false
    var body: some View {
        Group {
            if colorScheme == .dark && darkMark {
                Image(nsImage: image).resizable().colorInvert()
            } else {
                Image(nsImage: image).resizable()
            }
        }.task(id: image) { darkMark = Self.isDarkTransparentMark(image) }
    }
    static func isDarkTransparentMark(_ image: NSImage) -> Bool {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return false }
        var visible = 0, dark = 0, transparent = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 32)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 32)) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.alphaComponent < 0.1 { transparent += 1; continue }
                visible += 1
                let high = max(c.redComponent, c.greenComponent, c.blueComponent)
                let low = min(c.redComponent, c.greenComponent, c.blueComponent)
                if high < 0.35 && high - low < 0.12 { dark += 1 }
            }
        }
        return visible > 0 && transparent > 0 && Double(dark) / Double(visible) > 0.95
    }
}
