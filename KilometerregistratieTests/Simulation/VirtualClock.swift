import Foundation
@testable import Kilometerregistratie

/// Virtuele tijd voor scenario's. De tijd loopt alleen als een test dat zegt;
/// timers gaan af op hun eigen momenten tijdens `advance(to:)`.
@MainActor
final class VirtualClock: TimeSource {
    private(set) var now: Date
    /// FakeIOS zet dit uit zolang de app is opgeschort (A3).
    var timersEnabled = true

    private struct ScheduledTimer {
        let id: Int
        let interval: TimeInterval
        var nextFire: Date
        let action: @MainActor () async -> Void
    }
    private var timers: [ScheduledTimer] = []
    private var nextID = 0

    init(start: Date) {
        now = start
    }

    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) -> TimerHandle {
        let id = nextID
        nextID += 1
        timers.append(ScheduledTimer(id: id, interval: interval, nextFire: now.addingTimeInterval(interval), action: action))
        return TimerHandle { [weak self] in
            self?.timers.removeAll { $0.id == id }
        }
    }

    var nextTimerDate: Date? {
        guard timersEnabled else { return nil }
        return timers.map(\.nextFire).min()
    }

    func advance(to date: Date) async {
        while timersEnabled,
              let index = timers.indices.min(by: { timers[$0].nextFire < timers[$1].nextFire }),
              timers[index].nextFire <= date {
            let timer = timers[index]
            now = max(now, timer.nextFire)
            timers[index].nextFire = timer.nextFire.addingTimeInterval(timer.interval)
            await timer.action()
        }
        now = max(now, date)
    }

    func resumeTimers() async {
        timersEnabled = true
        // Een echte `Task.sleep` die door opschorten heen liep, vuurt na het
        // hervatten één keer en loopt daarna weer op zijn normale ritme.
        let overdue = timers.filter { $0.nextFire <= now }
        for timer in overdue {
            if let index = timers.firstIndex(where: { $0.id == timer.id }) {
                timers[index].nextFire = now.addingTimeInterval(timer.interval)
            }
            await timer.action()
        }
    }

    func removeAllTimers() {
        timers.removeAll()
    }
}
