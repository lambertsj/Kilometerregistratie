import XCTest
import SwiftData
@testable import Kilometerregistratie

final class ModelTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Trip.self, Vehicle.self, AppSettings.self, CachedAddress.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func testTripRoundTripsThroughStore() throws {
        let context = try makeInMemoryContext()
        let vehicle = Vehicle(name: "Bedrijfsauto", licensePlate: "AB-123-C")
        context.insert(vehicle)
        let trip = Trip(startDate: .now, distanceKm: 12.5, category: .commute, vehicle: vehicle)
        context.insert(trip)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.category, .commute)
        XCTAssertEqual(fetched.first?.distanceKm, 12.5)
        XCTAssertEqual(fetched.first?.vehicle?.licensePlate, "AB-123-C")
    }

    func testAppSettingsFetchOrCreateIsSingleton() throws {
        let context = try makeInMemoryContext()
        let first = AppSettings.fetchOrCreate(in: context)
        first.reimbursementRatePerKm = 0.21
        try context.save()

        let second = AppSettings.fetchOrCreate(in: context)
        XCTAssertEqual(second.reimbursementRatePerKm, 0.21)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppSettings>()).count, 1)
    }

    func testRoutePolylineEncodeDecode() throws {
        let points = [
            RoutePoint(latitude: 52.370, longitude: 4.895, offset: 0),
            RoutePoint(latitude: 52.371, longitude: 4.896, offset: 30),
        ]
        let data = try RoutePolyline.encode(points)
        XCTAssertEqual(try RoutePolyline.decode(data), points)
    }

    func testWorkWeekdaysRoundTrip() {
        let settings = AppSettings()
        XCTAssertEqual(settings.workWeekdays, [2, 3, 4, 5, 6])
        settings.workWeekdays = [1, 7]
        XCTAssertEqual(settings.workWeekdays, [1, 7])
    }

    func testCachedAddressRounding() {
        XCTAssertEqual(CachedAddress.rounded(52.37021), 52.370)
        XCTAssertEqual(CachedAddress.rounded(4.89568), 4.896)
    }

    func testLocationAccuracyPreferenceDefaultsToBalanced() {
        // Bestaande installaties zonder dit veld moeten via de lightweight
        // migration op "gebalanceerd" uitkomen, niet crashen of leeg zijn.
        XCTAssertEqual(AppSettings().locationAccuracyPreference, .balanced)
    }

    func testLocationAccuracyPreferenceRoundTrip() {
        let settings = AppSettings()
        settings.locationAccuracyPreference = .precise
        XCTAssertEqual(settings.locationAccuracyPreference, .precise)
        settings.locationAccuracyPreference = .batterySaver
        XCTAssertEqual(settings.locationAccuracyPreference, .batterySaver)
    }
}
