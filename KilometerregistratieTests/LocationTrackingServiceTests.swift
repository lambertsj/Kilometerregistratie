import XCTest
import SwiftData
@testable import Kilometerregistratie

@MainActor
final class LocationTrackingServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Trip.self, Vehicle.self, AppSettings.self, CachedAddress.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// Regressie: de watchdog, ingetrokken toestemming en het uitzetten van
    /// detectie sluiten een opname via `stopRecording(endDate:)`. Die zette
    /// de einddatum niet, waardoor de rit voor altijd "actief" bleef en
    /// nieuwe automatische ritten geblokkeerd werden.
    func testStopRecordingClosesAutomaticTripAtGivenEndDate() async throws {
        let context = try makeContext()
        let service = LocationTrackingService()
        service.configure(context: context)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(startDate: start, isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .automatic)

        let end = start.addingTimeInterval(20 * 60)
        await service.stopRecording(endDate: end)

        XCTAssertEqual(trip.endDate, end)
        XCTAssertNil(try TripRepository(context: context).activeTrip())
    }
}
