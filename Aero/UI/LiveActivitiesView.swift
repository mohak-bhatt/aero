import SwiftUI

/// One sidebar placement for media and future activity providers.
struct LiveActivitiesView: View {
    @ObservedObject var tabs: TabManager
    var onlyActivityID: UUID? = nil
    var includesMedia = true
    @ObservedObject private var store = LiveActivitiesStore.shared
    @State private var editing: LiveActivity?
    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.activities.filter { onlyActivityID == nil || $0.id == onlyActivityID }) { activity in
                HStack(spacing: 10) {
                    Image(systemName: symbol(activity.kind))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(activity.kind == .timer ? Color.orange : .accentColor)
                        .frame(width: 38, height: 38)
                        .background((activity.kind == .timer ? Color.orange : .accentColor).opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        Text(activity.status == .paused ? "Paused" : activity.detail).font(.caption).foregroundStyle(.secondary)
                        if let remaining = activity.pausedRemaining {
                            Text("\(Int(remaining) / 60):\(String(format: "%02d", Int(remaining) % 60))")
                                .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit()).foregroundStyle(.orange)
                        }
                        if activity.kind == .clock {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(context.date, style: .time).monospacedDigit()
                            }
                        }
                        if let value = activity.normalizedProgress { ProgressView(value: value).controlSize(.small) }
                        if let deadline = activity.deadline, activity.status == .running {
                            Text(deadline, style: .timer).font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit()).foregroundStyle(activity.kind == .timer ? Color.orange : .primary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if activity.kind == .timer && activity.status != .completed {
                        Button { store.toggleTimer(activity.id) } label: {
                            Image(systemName: activity.status == .paused ? "play.fill" : "pause.fill")
                        }.help(activity.status == .paused ? "Resume timer" : "Pause timer").foregroundStyle(.orange)
                    }
                    if let id = activity.tabID, let tab = tabs.tabs.first(where: { $0.id == id }) {
                        Button { tabs.selectTab(tab) } label: { Image(systemName: "arrow.up.right") }.help("Go to activity")
                    }
                    if activity.status == .completed || activity.status == .failed {
                        Button { store.remove(activity.id) } label: { Image(systemName: "xmark") }.help("Dismiss activity")
                    }
                }
                .contextMenu {
                    Button("Edit Activity…") { editing = activity }
                    Button("Dismiss Live Activity") { store.remove(activity.id) }
                }
                .buttonStyle(RubberButtonStyle()).padding(12)
                    .glass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if includesMedia { MediaCardView(tabs: tabs) }
        }
        .sheet(item: $editing) { ActivityEditor(activity: $0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live Activities")
    }
    private func symbol(_ kind: LiveActivity.Kind) -> String {
        switch kind {
        case .notification: return "bell"
        case .timer: return "timer"
        case .clock: return "clock"
        case .assistantTask: return "sparkles"
        case .timeLimit: return "hourglass"
        case .meeting: return "video"
        }
    }
}

struct ActivityToolDrawer: View {
    @EnvironmentObject private var state: BrowserState
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var tabs: TabManager
    let close: () -> Void
    @State private var editor: LiveActivity?
    @State private var downloadsOpen = false
    var body: some View {
        VStack(spacing: 16) {
            tool("Close menu", "chevron.left", .secondary, action: close)
            tool("Timer", "timer", .orange) {
                editor = LiveActivity(id: UUID(), kind: .timer, title: "Timer", detail: "")
            }
            tool("Clock", "clock", .blue) { LiveActivitiesStore.shared.addClock() }
            tool("Focus timer", "moon", .purple) {
                editor = LiveActivity(id: UUID(), kind: .timer, title: "Focus", detail: "")
            }
            Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 12)
            tool("History", "clock.arrow.circlepath", .gray) { state.showAllHistory() }
            tool("Bookmarks", "book", .gray) { state.toggleBookmarks(); close() }
            tool("Downloads", "arrow.down.circle", .gray) { downloadsOpen = true }
            tool("Settings", "gearshape", .gray) { openSettings() }
            Spacer()
        }
        .padding(.top, 60).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .popover(isPresented: $downloadsOpen) { DownloadsPopover(manager: .shared) }
        .sheet(item: $editor) { ActivityEditor(activity: $0) }
    }
    private func tool(_ title: String, _ symbol: String, _ accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .foregroundStyle(accent).frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
}

private struct ActivityEditor: View {
    let activity: LiveActivity
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var minutes = 5
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(activity.kind == .timer ? "Edit Timer" : "Edit Activity",
                  systemImage: activity.kind == .timer ? "timer" : "slider.horizontal.3")
                .font(.title2.weight(.semibold)).foregroundStyle(activity.kind == .timer ? .orange : .primary)
            TextField("Name", text: $title)
            if activity.kind == .timer {
                Stepper("\(minutes) minutes", value: $minutes, in: 1...1440)
                Text("Saving starts the countdown from this duration.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var updated = activity
                    updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if activity.kind == .timer {
                        updated.deadline = Date().addingTimeInterval(Double(minutes * 60))
                        updated.status = .running; updated.detail = ""; updated.pausedRemaining = nil
                    }
                    LiveActivitiesStore.shared.upsert(updated); dismiss()
                }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 320)
        .onAppear {
            title = activity.title
            if let deadline = activity.deadline { minutes = min(1440, max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))) }
        }
    }
}

/// Active content, rather than a permanent launcher, occupies the compact rail.
struct CompactLiveActivities: View {
    @ObservedObject var tabs: TabManager
    @ObservedObject private var store = LiveActivitiesStore.shared
    @ObservedObject private var media = MediaHub.shared
    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.activities) { activity in
                CompactActivityBubble(symbol: activitySymbol(activity), title: activity.title, tint: activityTint(activity), activity: activity) {
                    LiveActivitiesView(tabs: tabs, onlyActivityID: activity.id, includesMedia: false)
                }.contextMenu {
                    Button("Dismiss Live Activity") { store.remove(activity.id) }
                }
            }
            ForEach(tabs.tabs.filter { tab in media.items[tab.id] != nil && media.permits(tab.id, url: tab.url) && tab.id != tabs.selectedID && !tabs.splitIDs.contains(tab.id) }) { tab in
                CompactActivityBubble(symbol: media.items[tab.id]?.isVideo == true ? "play.rectangle" : "waveform", title: media.items[tab.id]?.title ?? "Now Playing", tint: media.items[tab.id]?.isVideo == true ? .purple : .pink, mediaInfo: media.items[tab.id]) {
                    MediaCardView(tabs: tabs, onlyTabID: tab.id)
                }.contextMenu {
                    Button("Go to Playing Tab") { tabs.selectTab(tab) }
                    Button("Dismiss Live Activity") { media.dismiss(tab.id) }
                }
            }
        }
    }
    private func activitySymbol(_ activity: LiveActivity) -> String {
        if activity.status == .completed { return "checkmark" }
        if activity.status == .failed { return "exclamationmark" }
        switch activity.kind {
        case .timer: return "timer"
        case .clock: return "clock"
        case .notification: return "bell.fill"
        case .assistantTask: return "sparkles"
        case .timeLimit: return "hourglass"
        case .meeting: return "video.fill"
        }
    }
    private func activityTint(_ activity: LiveActivity) -> Color {
        if activity.status == .failed { return .red }
        if activity.status == .completed { return .green }
        switch activity.kind {
        case .timer, .timeLimit: return .orange
        case .clock: return .cyan
        case .notification: return .yellow
        case .assistantTask: return .purple
        case .meeting: return .green
        }
    }

}

private struct CompactActivityBubble<Detail: View>: View {
    let symbol: String
    let title: String
    var tint: Color = .orange
    var activity: LiveActivity? = nil
    var mediaInfo: MediaInfo? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var detail: () -> Detail
    @State private var open = false
    @State private var dismissal: DispatchWorkItem?
    var body: some View {
        Button { open.toggle() } label: {
            VStack(spacing: 3) {
                ZStack {
                    if let info = mediaInfo {
                        if info.isVideo {
                            Image(systemName: info.isPlaying ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .bold))
                        } else { PlaybackIndicator(isPlaying: info.isPlaying, tint: tint) }
                    } else if activity?.kind == .clock {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Image(systemName: "clock")
                                .overlay { Rectangle().frame(width: 1, height: 7).offset(y: -3)
                                    .rotationEffect(.degrees(context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) * 6)) }
                        }
                    } else {
                        Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                            .symbolEffect(.pulse, options: .repeating, isActive: activity?.kind == .assistantTask && activity?.status == .running && !reduceMotion)
                    }
                }.frame(width: 24, height: 22)
                if let deadline = activity?.deadline, activity?.status == .running {
                    Text(deadline, style: .timer).font(.system(size: 8, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                } else if let info = mediaInfo, info.duration.isFinite, info.duration > 0, info.currentTime.isFinite {
                    Capsule().fill(tint.opacity(0.2)).frame(width: 22, height: 2)
                        .overlay(alignment: .leading) {
                            Capsule().fill(tint).frame(width: 22 * min(1, max(0, info.currentTime / info.duration)), height: 2)
                        }
                } else if activity?.status == .paused {
                    Image(systemName: "pause.fill").font(.system(size: 6))
                }
            }
            .foregroundStyle(tint).padding(.vertical, 6).frame(width: 34)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(open ? 0.55 : 0.2), lineWidth: 0.5))
            .scaleEffect(open ? 1.08 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: open)
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .onHover(perform: hovering)
        .popover(isPresented: $open, arrowEdge: .trailing) {
            detail().padding(10).frame(width: 280).onHover(perform: hovering)
        }
        .onDisappear { dismissal?.cancel() }
    }
    private func hovering(_ inside: Bool) {
        dismissal?.cancel()
        if inside { open = true }
        else {
            let work = DispatchWorkItem { open = false }
            dismissal = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }
}
