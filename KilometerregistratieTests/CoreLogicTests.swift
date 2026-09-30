import XCTest
@testable import Kilometerregistratie

final class CoreLogicTests: XCTestCase {
    // MARK: - GeoDistance

    func testHaversineAmsterdamUtrecht() {
        // Amsterdam Centraal → Utrecht Centraal is hemelsbreed ~35 km.
        let meters = GeoDistance.meters(
            fromLatitude: 52.3791, longitude: 4.9003,
            toLatitude: 52.0894, longitude: 5.1101
        )
        XCTAssertEqual(meters / 1000, 35, accuracy: 2)
    }

    func testRouteDistanceSumsSegments() {
        let points = [
            RoutePoint(latitude: 52.0, longitude: 5.0, offset: 0),
            RoutePoint(latitude: 52.01, longitude: 5.0, offset: 60),
            RoutePoint(latitude: 52.02, longitude: 5.0, offset: 120),
        ]
        // 0.02 graden latitude ≈ 2.22 km.
        XCTAssertEqual(GeoDistance.routeDistanceKm(points), 2.22, accuracy: 0.05)
        XCTAssertEqual(GeoDistance.routeDistanceKm([]), 0)
        XCTAssertEqual(GeoDistance.routeDistanceKm([points[0]]), 0)
    }

    // MARK: - MileageStatistics

    private func summary(_ km: Double, _ category: TripCategory, year: Int = 2026) -> TripSummary {
        var components = DateComponents()
        components.year = year
        components.month = 6
        components.day = 15
        return TripSummary(startDate: Calendar.current.date(from: components)!, distanceKm: km, category: category)
    }

    func testTotalsAndBreakdown() {
        let trips = [summary(100, .business), summary(50, .personal), summary(30, .commute), summary(20, .business)]
        XCTAssertEqual(MileageStatistics.totalKm(trips), 200)
        XCTAssertEqual(MileageStatistics.totalKm(trips, category: .business), 120)
        let breakdown = MileageStatistics.breakdown(trips)
        XCTAssertEqual(breakdown[.business], 120)
        XCTAssertEqual(breakdown[.personal], 50)
        XCTAssertEqual(breakdown[.commute], 30)
    }

    func testPrivateKmCounterRespectsYearBoundary() {
        let trips = [
            summary(300, .personal, year: 2026),
            summary(150, .personal, year: 2025),
            summary(400, .business, year: 2026),
        ]
        XCTAssertEqual(MileageStatistics.privateKm(in: 2026, trips: trips), 300)
        XCTAssertEqual(MileageStatistics.privateKm(in: 2025, trips: trips), 150)
    }

    func testPrivateKmStatusThresholds() {
        XCTAssertEqual(MileageStatistics.privateKmStatus(forYearTotal: 100), .ok)
        XCTAssertEqual(MileageStatistics.privateKmStatus(forYearTotal: 399.9), .ok)
        XCTAssertEqual(MileageStatistics.privateKmStatus(forYearTotal: 400), .nearingLimit)
        XCTAssertEqual(MileageStatistics.privateKmStatus(forYearTotal: 499.9), .nearingLimit)
        XCTAssertEqual(MileageStatistics.privateKmStatus(forYearTotal: 500), .overLimit)
    }

    func testReimbursement() {
        XCTAssertEqual(MileageStatistics.reimbursement(businessKm: 1000, ratePerKm: 0.23), 230, accuracy: 0.001)
    }

    /// FASE 3: een reeks bekende ritten die de 500 km-grens eerst nadert en
    /// vervolgens overschrijdt, met de status na elke rit.
    func testPrivateKmCounterNearsAndCrossesTheLimitTripByTrip() {
        var trips: [TripSummary] = []
        func add(_ km: Double) -> (total: Double, status: MileageStatistics.PrivateKmStatus) {
            trips.append(summary(km, .personal))
            let total = MileageStatistics.privateKm(in: 2026, trips: trips)
            return (total, MileageStatistics.privateKmStatus(forYearTotal: total))
        }

        XCTAssertEqual(add(150).status, .ok)
        XCTAssertEqual(add(150).status, .ok)          // 300 km: nog ruim onder de grens
        let nearing = add(120)                        // 420 km: nadert de grens
        XCTAssertEqual(nearing.total, 420)
        XCTAssertEqual(nearing.status, .nearingLimit)
        let crossed = add(90)                         // 510 km: over de grens
        XCTAssertEqual(crossed.total, 510)
        XCTAssertEqual(crossed.status, .overLimit)
    }
}
