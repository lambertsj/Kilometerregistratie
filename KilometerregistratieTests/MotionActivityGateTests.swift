import XCTest
@testable import Kilometerregistratie

final class MotionActivityGateTests: XCTestCase {
    func testAllowsStartWhenNoRecentSample() {
        // Geen CoreMotion-classificatie beschikbaar: val terug op snelheid.
        XCTAssertTrue(MotionActivityGate.allowsAutomaticStart(nil))
    }

    func testAllowsStartWhenAutomotive() {
        let sample = MotionActivityGate.ActivitySample(automotive: true, confidence: .high)
        XCTAssertTrue(MotionActivityGate.allowsAutomaticStart(sample))
    }

    func testBlocksStartWhenConfidentlyNotAutomotive() {
        // Scenario uit FASE 1.2: fietsen of OV dat toevallig de
        // snelheidsdrempel haalt, mag geen automatische rit starten.
        let sample = MotionActivityGate.ActivitySample(automotive: false, confidence: .high)
        XCTAssertFalse(MotionActivityGate.allowsAutomaticStart(sample))
    }

    func testAllowsStartWhenLowConfidenceEvenIfNotAutomotive() {
        // CoreMotion is zelf onzeker: niet blokkeren op een onbetrouwbare
        // classificatie.
        let sample = MotionActivityGate.ActivitySample(automotive: false, confidence: .low)
        XCTAssertTrue(MotionActivityGate.allowsAutomaticStart(sample))
    }
}
