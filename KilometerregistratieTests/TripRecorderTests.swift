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
        recorder.restoreActiveTrip(context: context)
        XCTAssertNil(recorder.activeTrip)

        try recorder.start(context: context, vehicle: nil)
        XCTAssertNotNil(recorder.activeTrip)

        // Dubbele start mag geen tweede rit aanmaken.
        try recorder.start(context: context, vehicle: nil)
        XCTAssertEqual(try TripRepository(context: context).trips().count, 1)

        let stopped = try recorder.stop(context: context)
        XCTAssertNotNil(stopped?.endDate)
        XCTAssertNil(recorder.activeTrip)
    }

    func testActiveTripSurvivesRestart() throws {
        let context = try makeContext()
        let first = TripRecorder()
        try first.start(context: context, vehicle: nil)

        let second = TripRecorder()
        second.restoreActiveTrip(context: context)
        XCTAssertEqual(second.activeTrip?.id, first.activeTrip?.id)
    }

    func testCancelDeletesTrip() throws {
        let context = try makeContext()
        let recorder = TripRecorder()
        try recorder.start(context: context, vehicle: nil)
        try recorder.cancel(context: context)
        XCTAssertNil(recorder.activeTrip)
        XCTAssertEqual(try TripRepository(context: context).trips().count, 0)
    }
}
