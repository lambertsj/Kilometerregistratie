import XCTest
@testable import Kilometerregistratie

final class GPSPointFilterTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ latitude: Double, _ longitude: Double, accuracy: Double = 10, secondsIn: TimeInterval) -> GPSPointFilter.Sample {
        GPSPointFilter.Sample(latitude: latitude, longitude: longitude, horizontalAccuracy: accuracy, timestamp: start.addingTimeInterval(secondsIn))
    }

    func testAcceptsFirstSampleRegardlessOfPrevious() {
        XCTAssertTrue(GPSPointFilter.accepts(sample(52.0, 5.0, secondsIn: 0), previous: nil))
    }

    func testRejectsInaccurateSample() {
        let previous = sample(52.0, 5.0, secondsIn: 0)
        let inaccurate = sample(52.001, 5.001, accuracy: 80, secondsIn: 10)
        XCTAssertFalse(GPSPointFilter.accepts(inaccurate, previous: previous))
    }

    func testAcceptsRealisticHighwaySpeed() {
        let previous = sample(52.0, 5.0, secondsIn: 0)
        // ~0.0004 graden ≈ 44 m in 2 s ≈ 22 m/s (~80 km/u): normale rijsnelheid.
        let next = sample(52.0004, 5.0, secondsIn: 2)
        XCTAssertTrue(GPSPointFilter.accepts(next, previous: previous))
    }

    func testRejectsPhysicallyImpossibleJump() {
        // Scenario uit FASE 1.3: een GPS-glitch in een tunnel/parkeergarage
        // laat het toestel "teleporteren" — 2 km in 1 seconde is geen auto.
        let previous = sample(52.0, 5.0, secondsIn: 0)
        let glitch = sample(52.02, 5.0, secondsIn: 1)
        XCTAssertFalse(GPSPointFilter.accepts(glitch, previous: previous))
    }

    func testAccuracyThresholdIsConfigurableForBatterySaverMode() {
        // FASE 1.4: in de batterijbesparende stand staat desiredAccuracy zelf
        // al grover, dus moet de ruisdrempel ruimer zijn om niet vrijwel elk
        // sample te verwerpen.
        let previous = sample(52.0, 5.0, secondsIn: 0)
        let coarse = sample(52.0004, 5.0, accuracy: 90, secondsIn: 10)
        XCTAssertFalse(GPSPointFilter.accepts(coarse, previous: previous))
        XCTAssertTrue(GPSPointFilter.accepts(coarse, previous: previous, maxHorizontalAccuracy: 120))
    }

    func testRejectsNonPositiveElapsedTime() {
        let previous = sample(52.0, 5.0, secondsIn: 10)
        let outOfOrder = sample(52.0001, 5.0, secondsIn: 10)
        XCTAssertFalse(GPSPointFilter.accepts(outOfOrder, previous: previous))
    }

    /// Bekende route (Amsterdam Centraal → Utrecht Centraal, ~35 km
    /// hemelsbreed) met tussenstappen, waar één GPS-glitch tussen zit. Na
    /// filtering moet de resterende afstand nog steeds dicht bij de
    /// werkelijke waarde liggen, ondanks de uitschieter.
    func testKnownRouteStaysAccurateDespiteInjectedOutlier() {
        var accepted: [GPSPointFilter.Sample] = []
        var lastAccepted: GPSPointFilter.Sample?

        let rawRoute: [GPSPointFilter.Sample] = [
            sample(52.3791, 4.9003, secondsIn: 0),      // Amsterdam Centraal
            sample(52.3200, 4.9600, secondsIn: 600),
            sample(60.0000, 10.000, accuracy: 5, secondsIn: 601), // GPS-glitch: "teleport"
            sample(52.2500, 5.0200, secondsIn: 1200),
            sample(52.0894, 5.1101, secondsIn: 1800),   // Utrecht Centraal
        ]

        for candidate in rawRoute where GPSPointFilter.accepts(candidate, previous: lastAccepted) {
            accepted.append(candidate)
            lastAccepted = candidate
        }

        XCTAssertEqual(accepted.count, rawRoute.count - 1, "de glitch moet eruit gefilterd zijn")

        let points = accepted.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude, offset: $0.timestamp.timeIntervalSince(start)) }
        XCTAssertEqual(GeoDistance.routeDistanceKm(points), 35, accuracy: 5)
    }
}
