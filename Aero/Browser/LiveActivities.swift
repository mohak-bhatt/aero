import Foundation
import Combine

/// Provider-neutral state for the Aero Engine's single Live Activities component.
/// Providers publish only real activity state; this model does not infer OS/app activity.
struct LiveActivity: Identifiable, Equatable {
    enum Kind: String { case notification, timer, clock, assistantTask, timeLimit, meeting }
    enum Status: String { case running, paused, completed, failed }
    let id: UUID
    var kind: Kind
    var title: String
    var detail: String
    var status: Status = .running
    var progress: Double? = nil
    var deadline: Date? = nil
    var tabID: UUID? = nil
    var pausedRemaining: TimeInterval? = nil

    var normalizedProgress: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }
}

@MainActor
final class LiveActivitiesStore: ObservableObject {
    static let shared = LiveActivitiesStore()
    @Published private(set) var activities: [LiveActivity] = []
    func upsert(_ activity: LiveActivity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) { activities[index] = activity }
        else { activities.append(activity) }
    }
    private var ticker: AnyCancellable?
    init() {
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            Task { @MainActor [weak self] in self?.advance(to: date) }
        }
    }
    func startTimer(seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0, seconds <= 86400 else { return }
        upsert(LiveActivity(id: UUID(), kind: .timer, title: "Timer", detail: "", deadline: Date().addingTimeInterval(seconds)))
    }
    func addClock() {
        guard !activities.contains(where: { $0.kind == .clock }) else { return }
        upsert(LiveActivity(id: UUID(), kind: .clock, title: "Local time", detail: TimeZone.current.identifier))
    }
    func advance(to date: Date) {
        for index in activities.indices where activities[index].kind == .timer && activities[index].status == .running {
            if let deadline = activities[index].deadline, deadline <= date {
                activities[index].status = .completed
                activities[index].detail = "Time’s up"
                activities[index].deadline = nil
            }
        }
    }
    func toggleTimer(_ id: UUID, now: Date = .now) {
        // Resolve expiry before a pause can resurrect an already finished timer.
        advance(to: now)
        guard let index = activities.firstIndex(where: { $0.id == id && $0.kind == .timer }) else { return }
        if activities[index].status == .running, let deadline = activities[index].deadline {
            activities[index].pausedRemaining = max(0, deadline.timeIntervalSince(now))
            activities[index].deadline = nil
            activities[index].status = .paused
        } else if activities[index].status == .paused, let remaining = activities[index].pausedRemaining {
            activities[index].deadline = now.addingTimeInterval(remaining)
            activities[index].pausedRemaining = nil
            activities[index].status = .running
        }
    }
    func remove(_ id: UUID) { activities.removeAll { $0.id == id } }
}
