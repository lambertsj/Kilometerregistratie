import XCTest
import SwiftData
@testable import Kilometerregistratie

final class RepositoryTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// Ritten aanmaken loopt sinds de audit trail via `TripWriteService`.
    /// Deze suite test het Nederlandse gedrag, dus met de NL-regelset.
    private func makeWriter(_ context: ModelContext) -> TripWriteService {
        TripWriteService(context: context, ruleSet: NetherlandsRuleSet())
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testTripFilteringByPeriodCategoryAndVehicle() throws {
        let context = try makeContext()
        let repo = TripRepository(context: context)
        let car = Vehicle(name: "Auto")
        let van = Vehicle(name: "Bus")
        context.insert(car)
        context.insert(van)

        try makeWriter(context).create(Trip(startDate: date(2026, 1, 10), endDate: date(2026, 1, 10), distanceKm: 10, category: .business, vehicle: car))
        try makeWriter(context).create(Trip(startDate: date(2026, 2, 5), endDate: date(2026, 2, 5), distanceKm: 20, category: .personal, vehicle: car))
        try makeWriter(context).create(Trip(startDate: date(2026, 2, 20), endDate: date(2026, 2, 20), distanceKm: 30, category: .business, vehicle: van))

        XCTAssertEqual(try repo.trips().count, 3)
        XCTAssertEqual(try repo.trips(from: date(2026, 2, 1)).count, 2)
        XCTAssertEqual(try repo.trips(category: .business).count, 2)
        XCTAssertEqual(try repo.trips(vehicleID: van.id).count, 1)
        XCTAssertEqual(try repo.trips(from: date(2026, 2, 1), category: .business, vehicleID: car.id).count, 0)

        // Nieuwste eerst.
        XCTAssertEqual(try repo.trips().first?.distanceKm, 30)
    }

    func testActiveTripIsUnfinishedTrip() throws {
        let context = try makeContext()
        let repo = TripRepository(context: context)
        XCTAssertNil(try repo.activeTrip())

        let running = Trip(startDate: .now)
        try makeWriter(context).create(running)
        XCTAssertEqual(try repo.activeTrip()?.id, running.id)

        running.endDate = .now
        try repo.save()
        XCTAssertNil(try repo.activeTrip())
    }

    func testVehicleDeleteKeepsTrips() throws {
        let context = try makeContext()
        let tripRepo = TripRepository(context: context)
        let vehicleRepo = VehicleRepository(context: context)

        let car = Vehicle(name: "Auto", initialOdometer: 50_000)
        try vehicleRepo.add(car)
        try makeWriter(context).create(Trip(startDate: date(2026, 3, 1), endDate: date(2026, 3, 1), distanceKm: 25, vehicle: car))

        XCTAssertEqual(vehicleRepo.estimatedOdometer(for: car), 50_025)

        try vehicleRepo.delete(car, ruleSet: NetherlandsRuleSet())
        let remaining = try tripRepo.trips()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNil(remaining.first?.vehicle)
    }

    func testMostRecentAutomaticTripIgnoresManualAndActiveTrips() throws {
        let context = try makeContext()
        let repo = TripRepository(context: context)

        try makeWriter(context).create(Trip(startDate: date(2026, 3, 1), endDate: date(2026, 3, 1), distanceKm: 5, isAutomaticallyRecorded: false))
        try makeWriter(context).create(Trip(startDate: date(2026, 3, 2), endDate: nil, distanceKm: 0, isAutomaticallyRecorded: true))
        let finishedAutomatic = Trip(startDate: date(2026, 3, 3), endDate: date(2026, 3, 3), distanceKm: 12, isAutomaticallyRecorded: true)
        try makeWriter(context).create(finishedAutomatic)

        XCTAssertEqual(try repo.mostRecentAutomaticTrip()?.id, finishedAutomatic.id)
    }

    func testMergeCombinesRouteAndDeletesLaterTrip() throws {
        let context = try makeContext()
        let repo = TripRepository(context: context)

        let earlier = Trip(
            startDate: date(2026, 3, 1), endDate: date(2026, 3, 1),
            startAddress: "Thuis", endAddress: "Station", distanceKm: 5,
            note: "Naar station", isAutomaticallyRecorded: true,
            routeData: try RoutePolyline.encode([RoutePoint(latitude: 52.0, longitude: 5.0, offset: 0)])
        )
        let later = Trip(
            startDate: date(2026, 3, 1).addingTimeInterval(600), endDate: date(2026, 3, 1).addingTimeInterval(1800),
            startAddress: "Station", endAddress: "Kantoor", distanceKm: 20,
            note: "Naar kantoor", isAutomaticallyRecorded: true,
            routeData: try RoutePolyline.encode([RoutePoint(latitude: 52.1, longitude: 5.1, offset: 0)])
        )
        try makeWriter(context).create(earlier)
        try makeWriter(context).create(later)

        try repo.merge(later, into: earlier, using: makeWriter(context))

        let remaining = try repo.trips()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(earlier.endAddress, "Kantoor")
        XCTAssertEqual(earlier.distanceKm, 25)
        XCTAssertEqual(earlier.endDate, later.endDate)
        let mergedPoints = try RoutePolyline.decode(earlier.routeData!)
        XCTAssertEqual(mergedPoints.count, 2)
    }
}
