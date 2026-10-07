import CoreMotion

@MainActor
protocol MotionProviding: AnyObject {
    var isAvailable: Bool { get }
    func start(handler: @escaping @MainActor (MotionActivityGate.ActivitySample) -> Void)
    func stop()
}

@MainActor
final class CoreMotionProvider: MotionProviding {
    private let manager = CMMotionActivityManager()

    var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    func start(handler: @escaping @MainActor (MotionActivityGate.ActivitySample) -> Void) {
        manager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            MainActor.assumeIsolated {
                handler(MotionActivityGate.ActivitySample(
                    automotive: activity.automotive,
                    confidence: MotionActivityGate.ActivitySample.Confidence(activity.confidence)
                ))
            }
        }
    }

    func stop() {
        manager.stopActivityUpdates()
    }
}

private extension MotionActivityGate.ActivitySample.Confidence {
    init(_ confidence: CMMotionActivityConfidence) {
        switch confidence {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        @unknown default: self = .low
        }
    }
}
