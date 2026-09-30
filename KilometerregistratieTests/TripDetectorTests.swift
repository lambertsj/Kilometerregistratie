import XCTest
@testable import Kilometerregistratie

final class TripDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(speed: Double, secondsIn: TimeInterval) -> TripDetector.Sample {
        TripDetector.Sample(latitude: 52.0, longitude: 5.0, speed: speed, timestamp: start.addingTimeInterval(secondsIn))
    }

    func testStartsOnDrivingSpeed() {
        var detector = TripDetector(stopAfterStationaryInterval: 180)
        XCTAssertEqual(detector.process(sample(speed: 1.0, secondsIn: 0)), .none)
        XCTAssertEqual(detector.process(sample(speed: -1, secondsIn: 5)), .none, "onbekende snelheid start geen rit")
        XCTAssertEqual(detector.process(sample(speed: 8.0, secondsIn: 10)), .tripStarted)
        XCTAssertEqual(detector.state, .moving)
    }

    func testShortStopDoesNotEndTrip() {
        var detector = TripDetector(stopAfterStationaryInterval: 180)
        _ = detector.process(sample(speed: 10, secondsIn: 0))
        // Stoplicht: 60 s stilstand blijft binnen de drempel.
        XCTAssertEqual(detector.process(sample(speed: 0, secondsIn: 60)), .none)
        XCTAssertEqual(detector.process(sample(speed: 0, secondsIn: 120)), .none)
        XCTAssertEqual(detector.process(sample(speed: 12, secondsIn: 150)), .none)
        XCTAssertEqual(detector.state, .moving)
    }

    func testLongStationaryEndsTripAtLastMovement() {
        var detector = TripDetector(stopAfterStationaryInterval: 180)
        _ = detector.process(sample(speed: 10, secondsIn: 0))
        _ = detector.process(sample(speed: 10, secondsIn: 100))
        XCTAssertEqual(detector.process(sample(speed: 0, secondsIn: 200)), .none)
        // 100 + 180 = 280 s: drempel bereikt; einde valt op het laatste beweegmoment.
        XCTAssertEqual(
            detector.process(sample(speed: 0, secondsIn: 280)),
            .tripEnded(endDate: start.addingTimeInterval(100))
        )
        XCTAssertEqual(detector.state, .idle)
    }

    func testResetReturnsToIdle() {
        var detector = TripDetector(stopAfterStationaryInterval: 180)
        _ = detector.process(sample(speed: 10, secondsIn: 0))
        detector.reset()
        XCTAssertEqual(detector.state, .idle)
        XCTAssertEqual(detector.process(sample(speed: 10, secondsIn: 10)), .tripStarted)
    }
}
