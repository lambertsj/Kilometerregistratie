import Foundation

/// Annuleerbare herhalende taak van een `TimeSource`.
@MainActor
final class TimerHandle {
    private let onCancel: () -> Void
    private(set) var isCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

/// Bron van tijd en herhalende timers. De service gebruikt dit in plaats van
/// `Date.now` en `Task.sleep`, zodat tests de tijd zelf kunnen laten lopen.
@MainActor
protocol TimeSource: AnyObject {
    var now: Date { get }
    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) -> TimerHandle
}

@MainActor
final class SystemTimeSource: TimeSource {
    var now: Date { .now }

    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) -> TimerHandle {
        let task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await action()
            }
        }
        return TimerHandle { task.cancel() }
    }
}
