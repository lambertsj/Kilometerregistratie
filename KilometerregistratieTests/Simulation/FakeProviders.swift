import Foundation
import SwiftData
@testable import Kilometerregistratie

@MainActor
final class FakeMotionProvider: MotionProviding {
    var isAvailable = true
    private(set) var isRunning = false
    private var handler: (@MainActor (MotionActivityGate.ActivitySample) -> Void)?

    func start(handler: @escaping @MainActor (MotionActivityGate.ActivitySample) -> Void) {
        isRunning = true
        self.handler = handler
    }

    func stop() {
        isRunning = false
        handler = nil
    }

    func send(automotive: Bool, confidence: MotionActivityGate.ActivitySample.Confidence = .high) {
        handler?(MotionActivityGate.ActivitySample(automotive: automotive, confidence: confidence))
    }

    func resetForNewProcess() {
        isRunning = false
        handler = nil
    }
}

/// Geeft altijd hetzelfde adres terug; raakt het netwerk niet.
@MainActor
struct FakeAddressResolver: AddressResolving {
    func address(latitude: Double, longitude: Double, context: ModelContext) async -> String? {
        "Teststraat 1"
    }
}
