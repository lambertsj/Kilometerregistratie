import XCTest
@testable import Kilometerregistratie

extension ScenarioRunner {
    /// Eisen die voor élk scenario gelden (zie spec, hoofdstuk 6).
    func assertInvariants(file: StaticString = #filePath, line: UInt = #line) throws {
        let all = trips

        // 1. Nooit meer dan één open rit.
        XCTAssertLessThanOrEqual(all.filter { $0.endDate == nil }.count, 1, "meer dan één open rit", file: file, line: line)

        // 2. endDate >= startDate en geen overlap tussen afgesloten ritten.
        let closed = all.filter { $0.endDate != nil }
        for trip in closed {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(trip.endDate), trip.startDate, "einde vóór start", file: file, line: line)
        }
        for (a, b) in zip(closed, closed.dropFirst()) {
            XCTAssertLessThanOrEqual(try XCTUnwrap(a.endDate), b.startDate, "overlappende ritten", file: file, line: line)
        }

        // 4. Einde van een automatische rit ligt niet later dan het laatste
        //    beweegmoment + drempel + 60 s (watchdog-marge) + 30 s (timer) + 1 s.
        let slack = TimeInterval(stopAfterMinutes * 60) + 60 + 30 + 1
        for trip in closed where trip.isAutomaticallyRecorded {
            let end = try XCTUnwrap(trip.endDate)
            let lastMovement = truthMovementTimes.last { $0 <= end } ?? trip.startDate
            XCTAssertLessThanOrEqual(
                end.timeIntervalSince(lastMovement), slack,
                "rit eindigt \(Int(end.timeIntervalSince(lastMovement))) s na het laatste beweegmoment",
                file: file, line: line
            )
        }

        // 5/6. Nooit meer afstand dan er is gereden (gaten tellen niet mee).
        let registeredMeters = all.reduce(0) { $0 + $1.distanceKm * 1000 }
        XCTAssertLessThanOrEqual(
            registeredMeters, truthDrivenMeters * 1.03 + 100,
            "meer afstand geregistreerd dan gereden", file: file, line: line
        )
    }

    /// Invariant 3: na afloop staat er geen open automatische rit meer. Alleen
    /// aanroepen als de app draait en er lang genoeg is gewacht.
    func assertNoOpenAutomaticTrip(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            openTrips.filter(\.isAutomaticallyRecorded).isEmpty,
            "open automatische rit na afloop", file: file, line: line
        )
    }
}
