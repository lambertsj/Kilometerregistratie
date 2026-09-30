import XCTest
@testable import Kilometerregistratie

final class HangingTripRecoveryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testResumesWhenGapIsShort() {
        let action = HangingTripRecovery.decide(
            lastKnownActivity: start,
            now: start.addingTimeInterval(5 * 60)
        )
        XCTAssertEqual(action, .resume)
    }

    func testFinalizesWhenAppWasKilledForALongTime() {
        // Scenario uit FASE 1.1: de app wordt tijdens een rit gekilld en pas
        // uren later weer geopend. Doorgaan met opnemen zou het hele
        // "gat" onterecht als rijtijd meetellen.
        let lastKnownActivity = start
        let action = HangingTripRecovery.decide(
            lastKnownActivity: lastKnownActivity,
            now: start.addingTimeInterval(3 * 3600)
        )
        XCTAssertEqual(action, .finalize(endDate: lastKnownActivity))
    }

    func testBoundaryAtMaxGap() {
        let lastKnownActivity = start
        XCTAssertEqual(
            HangingTripRecovery.decide(lastKnownActivity: lastKnownActivity, now: start.addingTimeInterval(30 * 60 - 1)),
            .resume
        )
        XCTAssertEqual(
            HangingTripRecovery.decide(lastKnownActivity: lastKnownActivity, now: start.addingTimeInterval(30 * 60)),
            .finalize(endDate: lastKnownActivity)
        )
    }
}
