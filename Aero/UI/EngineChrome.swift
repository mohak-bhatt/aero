import SwiftUI

/// The same views render on every edge. Orientation changes layout, never control style.
struct EngineWorkspace<Page: View>: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var model: EngineModel
    @ViewBuilder var page: () -> Page
    var body: some View {
        GeometryReader { geometry in
            let count = [EngineConfiguration.Dock.left, .right].filter { edge in state.engineEditing || model.configuration.placements.contains(where: { $0.dock == edge }) }.count
            let budget = max(52, (geometry.size.width - 320) / CGFloat(max(1, count)))
            let side: CGFloat = model.configuration.compact ? 52 : min(budget, max(200, min(state.sidebarWidth, 360)))
            VStack(spacing: 0) {
                if !model.configuration.compact || !model.configuration.primary.vertical || !state.sidebarVisible {
                    HStack { Spacer(); if !state.sidebarVisible { Button("Show controls") { state.sidebarVisible = true }.padding(.trailing, 12) } }
                        .frame(height: state.rowHeight).background(WindowDragArea())
                }
                dock(.top, width: geometry.size.width)
                HStack(spacing: 0) {
                    dock(.left, width: side)
                    page().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GeometryReader { proxy in
                            Color.clear.onAppear { state.engineContentRect = proxy.frame(in: .named("aeroWindow")) }
                                .onChange(of: proxy.frame(in: .named("aeroWindow"))) { _, rect in state.engineContentRect = rect }
                        })
                    dock(.right, width: side)
                }.frame(maxHeight: .infinity)
                dock(.bottom, width: geometry.size.width)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if state.engineEditing { EngineEditorBar(state: state, model: model) }
        }
    }
    @ViewBuilder private func dock(_ edge: EngineConfiguration.Dock, width: CGFloat) -> some View {
        let items = model.configuration.placements.filter { $0.dock == edge }
        if state.engineEditing || (state.sidebarVisible && !items.isEmpty) {
            EngineEdge(state: state, model: model, edge: edge, width: width)
                .frame(width: edge.vertical ? width : nil)
                .frame(maxHeight: edge.vertical ? .infinity : nil)
        }
    }
}

private struct EngineEdge: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var model: EngineModel
    let edge: EngineConfiguration.Dock
    let width: CGFloat
    @State private var targeted = false
    private var narrow: Bool { edge.vertical && model.configuration.compact }
    private var items: [EngineConfiguration.Placement] { model.configuration.placements.filter { $0.dock == edge } }
    var body: some View {
        VStack(spacing: 4) {
            if narrow && model.configuration.primary == edge { VerticalTrafficLights().frame(height: 84) }
            ScrollView(.vertical) {
                EngineFlow(spacing: 6) {
                    ForEach(items) { item in
                        EngineElementView(state: state, tabs: state.tabs, model: model, item: item, vertical: edge.vertical, narrow: narrow)
                            .frame(width: elementWidth(item.element))
                            .modifier(EngineDragElement(state: state, model: model, item: item))
                    }
                    if items.isEmpty { Text("Drop here").font(.caption).foregroundStyle(.secondary).frame(width: max(30, width - 16), height: 32) }
                }.padding(narrow ? 5 : 8)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: edge.vertical ? .infinity : 140)
        }
        .background { SidebarBackground(tint: state.tabs.selectedTab?.themeColor.map(Color.init(nsColor:)), isOverlay: false) }
        .overlay { if state.engineEditing { RoundedRectangle(cornerRadius: 10).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4])) } }
        .dropDestination(for: String.self) { strings, _ in
            guard state.engineEditing, let raw = strings.first, raw.hasPrefix("aero.element."), let element = EngineConfiguration.Element(rawValue: String(raw.dropFirst(13))) else { return false }
            model.update { $0.move(element, to: edge) }; AeroHaptics.perform(.alignment); return true
        } isTargeted: { targeted = $0 }
        .background {
            if model.configuration.primary == edge {
                SidebarSwipeSurface(width: state.activitiesRevealWidth) { state.activitiesDragWidth = $0 } settle: { open in
                    state.activitiesDragWidth = nil; state.activitiesDrawerOpen = open
                }
            }
        }
        .popover(isPresented: Binding(get: { model.configuration.primary == edge && state.activitiesDrawerOpen }, set: { state.activitiesDrawerOpen = $0 }), arrowEdge: edge.vertical ? .trailing : .bottom) {
            ActivityToolDrawer(tabs: state.tabs) { state.activitiesDrawerOpen = false }.frame(width: 52, height: 450)
        }
    }
    private func elementWidth(_ element: EngineConfiguration.Element) -> CGFloat {
        if narrow { return 42 }
        switch element {
        case .tabs: return max(150, width - 16)
        case .favorites: return edge.vertical ? width - 16 : min(max(44, CGFloat(state.favorites.items.count) * 56), width - 16)
        case .pins: return edge.vertical ? width - 16 : min(max(36, CGFloat(state.tabs.pinnedTabs.count) * 38), width - 16)
        case .address: return edge.vertical ? width - 16 : min(480, max(220, width * 0.45))
        case .activities: return edge.vertical ? width - 16 : 40
        case .bookmarks, .newTab: return 56
        case .updates: return narrow ? 42 : 130
        default: return 36
        }
    }
}

/// Wraps controls into available space instead of covering the web or clipping controls.
struct EngineFlow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 270, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading, proposal: .unspecified)
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; row = max(row, size.height)
        }
        return (CGSize(width: width, height: y + row), points)
    }
}

private struct EngineDragElement: ViewModifier {
    @ObservedObject var state: BrowserState
    @ObservedObject var model: EngineModel
    let item: EngineConfiguration.Placement
    func body(content: Content) -> some View {
        if state.engineEditing {
            content.allowsHitTesting(false)
                .overlay { Color.clear.contentShape(Rectangle()) }
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3])) }
                .contentShape(Rectangle())
                .draggable("aero.element." + item.element.rawValue)
                .help("Drag \(item.element.title) to an edge or before another element")
                .contextMenu {
                    ForEach(EngineConfiguration.Dock.allCases) { dock in
                        Button("Move to " + dock.title) { model.update { $0.move(item.element, to: dock) } }
                    }
                }
                .dropDestination(for: String.self) { strings, _ in
                    guard let raw = strings.first, raw.hasPrefix("aero.element."), let element = EngineConfiguration.Element(rawValue: String(raw.dropFirst(13))) else { return false }
                    model.update { $0.move(element, to: item.dock, before: item.element) }; return true
                }
        } else { content }
    }
}

private struct EngineElementView: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var tabs: TabManager
    @ObservedObject var model: EngineModel
    let item: EngineConfiguration.Placement
    let vertical: Bool
    let narrow: Bool
    @Environment(\.openSettings) private var openSettings
    @State private var open = false
    var body: some View {
        Group {
            if let tab = tabs.selectedTab {
                switch item.element {
                case .sidebar:
                    ChromeToggleButton(iconSize: 16, help: "Hide controls; hold to customize") { state.toggleSidebar() }
                case .back, .forward:
                    NavigationArrow(tab: tab, back: item.element == .back, height: 32, iconSize: item.large ? 19 : 16)
                case .reload:
                    Button { tab.reloadOrStop() } label: { Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise").contentTransition(.symbolEffect(.replace)).frame(width: 32, height: 32) }.buttonStyle(RubberButtonStyle()).help("Reload or Stop")
                case .pageMenu: PageMenuButton(tab: tab, state: state, manager: tabs)
                case .address:
                    if narrow {
                        iconButton("magnifyingglass") { open = true }.popover(isPresented: $open) {
                            OmniboxView(tab: tab, state: state, height: 34, includesPageControls: false).padding(12).frame(width: 330)
                        }
                    } else { OmniboxView(tab: tab, state: state, height: 34, includesPageControls: false) }
                case .tabs, .pins: tabCollection
                case .favorites: EngineFavorites(state: state, tabs: tabs, favorites: state.favorites, vertical: vertical, narrow: narrow)
                case .newTab:
                    GlassButton(.capsule, help: "New tab", width: narrow ? 32 : 52, height: 30, action: { state.newTab() }) { Image(systemName: "plus") }
                case .activities:
                    if narrow { CompactLiveActivities(tabs: tabs) }
                    else if vertical { LiveActivitiesView(tabs: tabs) }
                    else { iconButton("waveform") { open = true }.popover(isPresented: $open) { LiveActivitiesView(tabs: tabs).frame(width: 280).padding(10) } }
                case .updates: UpdateNowButton(compact: true)
                case .downloads: DownloadsButton(diameter: 32, iconSize: 18)
                case .share: ShareButton(url: tab.url, diameter: 32, iconSize: 17)
                case .bookmarks:
                    GlassButton(.capsule, help: "Bookmarks", width: narrow ? 32 : 52, height: 32, action: { open = true }) { Image(systemName: "chevron.compact.up") }
                        .popover(isPresented: $open) { BookmarksPanel(store: state.bookmarks, state: state, maxHeight: 400).frame(width: 280) }
                case .history: iconButton("clock") { state.showAllHistory() }
                case .settings: iconButton("gearshape") { openSettings() }
                }
            }
        }
        .frame(minHeight: state.engineEditing ? 36 : nil)
        .scaleEffect(item.large ? 1.08 : 1)
        .padding(item.large ? 2 : 0)
        .font(.system(size: item.large ? 18 : 15, weight: .medium))
        .accessibilityLabel(item.element.title)
        .overlay(alignment: .bottom) { if state.engineEditing { Text(item.element.title).font(.system(size: 8)).padding(2).background(.regularMaterial, in: Capsule()).allowsHitTesting(false) } }
    }
    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 32, height: 32) }.buttonStyle(RubberButtonStyle())
    }
    private var tabCollection: some View {
        let list = item.element == .pins ? tabs.pinnedTabs : tabs.unpinnedTabs
        return ScrollView(vertical ? .vertical : .horizontal) {
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
            layout {
                ForEach(list) { tab in
                    Group {
                        if model.configuration.compact || item.element == .pins {
                            PinnedTabTile(tab: tab, cell: 32, isSelected: tab.id == tabs.selectedID, onSelect: { tabs.selectTab(tab) }, onUnpin: { tabs.togglePin(tab) }, onFavorite: { state.toggleFavorite(tab) }, onClose: { tabs.closeTab(tab) })
                        } else {
                            SidebarTabRow(tab: tab, size: state.sidebarSize, isSelected: tab.id == tabs.selectedID, onSelect: { tabs.selectTab(tab) }, onClose: { tabs.closeTab(tab) }, onPin: { tabs.togglePin(tab) }, onFavorite: { state.toggleFavorite(tab) })
                                .frame(width: vertical ? nil : 200)
                                .modifier(TabHoverPreview(tab: tab, showsSplitBadge: false))
                        }
                    }.gesture(DragGesture(minimumDistance: 6)
                        .onChanged { _ in if !state.engineEditing { state.dragMoved(tab) } }
                        .onEnded { value in
                            guard !state.engineEditing else { return }
                            if state.dragEnded(tab) { return }
                            guard let index = list.firstIndex(where: { $0.id == tab.id }) else { return }
                            let distance = vertical ? value.translation.height : value.translation.width
                            let stride: CGFloat = vertical || model.configuration.compact ? 38 : 204
                            let target = min(max(index + Int((distance / stride).rounded()), 0), list.count - 1)
                            if target != index { tabs.move(tab, to: list[target]) }
                        })
                }
                if list.isEmpty && state.engineEditing { Text(item.element.title).font(.caption).frame(height: 32) }
            }
        }.scrollIndicators(.hidden).frame(height: vertical ? min(CGFloat(max(1, list.count)) * 38, 320) : 36)
    }
}

private struct EngineFavorites: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var tabs: TabManager
    @ObservedObject var favorites: FavoritesStore
    let vertical: Bool
    let narrow: Bool
    var body: some View {
        ScrollView(.horizontal) {
            let layout = narrow ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
            layout {
                ForEach(favorites.items) { favorite in
                    let live = tabs.favoriteTab(for: favorite)
                    FavoriteTile(favorite: favorite, liveTab: live, cell: narrow ? 32 : state.sidebarSize.favoriteCell, isCurrent: live?.id == tabs.selectedID, onOpen: { state.openFavorite(favorite) }, onCloseTab: { if let live { tabs.closeTab(live) } }, onRemove: { state.removeFavorite(favorite) })
                }
            }
        }.scrollIndicators(.hidden).frame(height: narrow ? CGFloat(favorites.items.count) * 38 : (favorites.items.isEmpty ? 0 : state.sidebarSize.favoriteCell))
    }
}

struct EngineEditorBar: View {
    @ObservedObject var state: BrowserState
    @ObservedObject var model: EngineModel
    @State private var selected = EngineConfiguration.Element.address
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Aero Engine").font(.headline)
                Text("Drag the actual controls. Drop on an edge or before another control.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Undo", action: model.undo).disabled(model.undoStack.isEmpty)
                Button("Redo", action: model.redo).disabled(model.redoStack.isEmpty)
                Button("Cancel") { finish(cancel: true) }.keyboardShortcut(.cancelAction)
                Button("Done") { finish(cancel: false) }.keyboardShortcut(.defaultAction)
            }
            ScrollView(.horizontal) { HStack {
                Menu("Presets") {
                    ForEach(EngineConfiguration.Dock.allCases.filter { $0 != .hidden }) { dock in
                        Button(dock.title + " · Standard") { model.update { $0 = .preset(dock) } }
                        Button(dock.title + " · Compact") { model.update { $0 = .preset(dock, compact: true) } }
                    }
                }
                Picker("Element", selection: $selected) { ForEach(EngineConfiguration.Element.allCases) { Text($0.title).tag($0) } }.frame(width: 190)
                Picker("Placement", selection: Binding(get: { model.configuration.placements.first(where: { $0.element == selected })?.dock ?? .hidden }, set: { edge in model.update { $0.move(selected, to: edge) } })) {
                    ForEach(EngineConfiguration.Dock.allCases) { Text($0.title).tag($0) }
                }.frame(width: 160)
                Button("Move earlier") { move(-1) }
                Button("Move later") { move(1) }
                Toggle("Large", isOn: Binding(get: { model.configuration.placements.first(where: { $0.element == selected })?.large ?? false }, set: { value in model.update { config in if let i = config.placements.firstIndex(where: { $0.element == selected }) { config.placements[i].large = value } } }))
                Spacer()
                Button("Reset") { model.update { $0 = .preset() } }
            }.controlSize(.small) }.scrollIndicators(.hidden)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(model.configuration.placements.filter { $0.dock == .hidden }) { item in
                        Label(item.element.title, systemImage: item.element.symbol).font(.caption).padding(7).background(.quaternary, in: Capsule()).draggable("aero.element." + item.element.rawValue)
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(12).background(.regularMaterial)
    }
    private func move(_ direction: Int) {
        model.update { config in
            guard let i = config.placements.firstIndex(where: { $0.element == selected }) else { return }
            let j = i + direction
            guard config.placements.indices.contains(j) else { return }
            config.placements.swapAt(i, j)
        }
    }
    private func finish(cancel: Bool) {
        model.finish(cancel: cancel); state.engineEditing = false
        if Onboarding.needed || Onboarding.resumeAfterCustomization { Onboarding.resumeAfterCustomization = false; Onboarding.show() }
    }
}
