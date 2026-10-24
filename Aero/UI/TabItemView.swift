import SwiftUI

struct TabItemView: View {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    @State private var hoveringClose = false

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        HStack(spacing: 6) {
            TabFavicon(tab: tab)

            Text(tab.displayTitle)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.primary.opacity(hoveringClose ? 0.14 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hoveringClose = $0 }
                .help("Close Tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background {
            if !isSelected {
                shape.fill(Color.primary.opacity(hovering ? 0.07 : 0))
            }
        }
        .modifier(SelectedGlass(isSelected: isSelected, shape: shape))
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}
