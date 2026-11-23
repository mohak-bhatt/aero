import SwiftUI
import WebKit

/// Puzzle-piece button that sits beside the address field, like Safari's extensions button.
struct ExtensionsButton: View {
    @ObservedObject private var manager = ExtensionManager.shared
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(RubberButtonStyle())
        .opacity(0.85)
        .help("Extensions")
        .popover(isPresented: $open, arrowEdge: .bottom) { ExtensionsPanel(manager: manager) }
        .onReceive(manager.$popup) { if $0 != nil { open = true } }
    }
}

struct ExtensionsPanel: View {
    @ObservedObject var manager: ExtensionManager

    var body: some View {
        if let popup = manager.popup {
            VStack(spacing: 0) {
                HStack {
                    Button { manager.popup = nil } label: { Image(systemName: "chevron.left") }.buttonStyle(RubberButtonStyle())
                    Text(popup.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(10)
                WebViewHost(webView: popup.webView).frame(width: 340, height: 440)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Extensions").font(.system(size: 13, weight: .semibold))

                if !manager.items.isEmpty {
                    ForEach(manager.items) { item in
                        HStack(spacing: 10) {
                            Group {
                                if let icon = item.context.webExtension.icon(for: CGSize(width: 28, height: 28)) {
                                    Image(nsImage: icon).resizable()
                                } else {
                                    Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(item.version).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open") { manager.perform(item) }.controlSize(.small)
                            Button { manager.remove(item) } label: { Image(systemName: "trash") }
                                .buttonStyle(RubberButtonStyle()).foregroundStyle(.secondary).help("Remove")
                        }
                    }
                }

                if !manager.available.isEmpty {
                    Text("On this Mac").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(manager.available) { found in
                        HStack(spacing: 10) {
                            Image(systemName: "puzzlepiece.extension").frame(width: 24).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(found.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(found.appName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Add") { Task { await manager.install(from: found.appex) } }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }
                }

                if manager.items.isEmpty && manager.available.isEmpty {
                    Text("No Safari extensions found on this Mac yet.").font(.system(size: 12)).foregroundStyle(.secondary)
                }

                Divider()
                HStack {
                    Button("Get Extensions…") { manager.openExtensionStore() }
                    Spacer()
                    Menu("More") {
                        Button("Add Unpacked Extension…") { manager.chooseAndInstall() }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                .font(.system(size: 12))
            }
            .padding(14)
            .frame(width: 320)
            .onAppear { manager.scanAvailable() }
        }
    }
}
