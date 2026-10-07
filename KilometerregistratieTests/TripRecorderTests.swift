import XCTest
import SwiftData
@testable import Kilometerregistratie

@MainActor
final class TripRecorderTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Trip.self, Vehicle.self, AppSettings.self, CachedAddress.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    func testStartStopFlow() throws {
        let context = try makeContext()
        let recorder = TripRecorder()
        XCTAssertNil(try TripRepository(context: context).activeTrip())

        try recorder.start(context: context, vehicle: nil)
        XCTAssertNotNil(try TripRepository(context: context).activeTrip())

        // Dubbele start mag geen tweede rit aanmaken.
        try recorder.start(context: context, vehicle: nil)
        XCTAssertEqual(try TripRepository(context: context).trips().count, 1)

        let stopped = try recorder.stop(context: context)
        XCTAssertNotNil(stopped?.endDate)
        XCTAssertNil(try TripRepository(context: context).activeTrip())
    }

    func testActiveTripSurvivesRestart() throws {
        let context = try makeContext()
        let started = try TripRecorder().start(context: context, vehicle: nil)
        XCTAssertNotNil(started)
        XCTAssertEqual(try TripRepository(context: context).activeTrip()?.id, started?.id)
    }

    func testCancelDeletesTrip() throws {
        let context = try makeContext()
        let recorder = TripRecorder()
        try recorder.start(context: context, vehicle: nil)
        try recorder.cancel(context: context)
        XCTAssertNil(try TripRepository(context: context).activeTrip())
        XCTAssertEqual(try TripRepository(context: context).trips().count, 0)
    }

    /// Een automatische rit wordt door de service gestart, niet door de
    /// recorder. STOP moet die rit toch kunnen afsluiten.
    func testStopClosesTripStartedElsewhere() throws {
        let context = try makeContext()
        let trip = Trip(startDate: .now.addingTimeInterval(-600), isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)

        let stopped = try TripRecorder().stop(context: context)
        XCTAssertEqual(stopped?.id, trip.id)
        XCTAssertNotNil(trip.endDate)
    }

    func testStartDoesNotCreateSecondTripNextToTripStartedElsewhere() throws {
        let context = try makeContext()
        try TripWriteService(context: context).create(Trip(startDate: .now, isAutomaticallyRecorded: true))

        try TripRecorder().start(context: context, vehicle: nil)
        XCTAssertEqual(try TripRepository(context: context).trips().count, 1)
    }

    func testRecorderUsesInjectedClock() throws {
        let context = try makeContext()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var current = t0
        let recorder = TripRecorder(now: { current })

        let trip = try XCTUnwrap(try recorder.start(context: context, vehicle: nil))
        XCTAssertEqual(trip.startDate, t0)

        current = t0.addingTimeInterval(900)
        let stopped = try recorder.stop(context: context)
        XCTAssertEqual(stopped?.endDate, t0.addingTimeInterval(900))
    }
}
