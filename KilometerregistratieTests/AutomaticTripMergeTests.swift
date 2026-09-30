import XCTest
@testable import Kilometerregistratie

final class AutomaticTripMergeTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testMergesShortlyAfterPreviousTripEnded() {
        // Scenario uit FASE 1.2: een trein stopt kort op een station en trekt
        // binnen enkele minuten weer op.
        XCTAssertTrue(AutomaticTripMerge.shouldMerge(
            previousTripEndDate: start,
            newTripStartDate: start.addingTimeInterval(2 * 60)
        ))
    }

    func testDoesNotMergeAfterLongGap() {
        XCTAssertFalse(AutomaticTripMerge.shouldMerge(
            previousTripEndDate: start,
            newTripStartDate: start.addingTimeInterval(6 * 60)
        ))
    }

    func testDoesNotMergeWithoutAPreviousTrip() {
        XCTAssertFalse(AutomaticTripMerge.shouldMerge(previousTripEndDate: nil, newTripStartDate: start))
    }

    func testBoundaryAtMergeWindow() {
        XCTAssertTrue(AutomaticTripMerge.shouldMerge(
            previousTripEndDate: start,
            newTripStartDate: start.addingTimeInterval(5 * 60)
        ))
        XCTAssertFalse(AutomaticTripMerge.shouldMerge(
            previousTripEndDate: start,
            newTripStartDate: start.addingTimeInterval(5 * 60 + 1)
        ))
    }
}
