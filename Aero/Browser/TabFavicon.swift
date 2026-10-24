import SwiftUI

/// Favicon, spinner while loading, or a placeholder glyph. Shared by all tab layouts.
struct TabFavicon: View {
    @ObservedObject var tab: BrowserTab
    var size: CGFloat = 16

    var body: some View {
        Group {
            if tab.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.75 * size / 16)
            } else if let image = tab.favicon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Image(systemName: tab.url == nil ? "house" : "globe")
                    .font(.system(size: size * 0.75))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
