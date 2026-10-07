import XCTest
import SwiftData
import CoreLocation
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

    /// Een opgeschorte app voert de watchdog-timer niet uit. Bij terugkeer
    /// naar de voorgrond moet de controle direct kunnen draaien en een rit
    /// zonder samples afsluiten op het laatste sample, niet op `now`.
    func testWatchdogCheckClosesTripAfterGPSSilence() async throws {
        let context = try makeContext()
        let service = LocationTrackingService()
        service.configure(context: context)

        let trip = Trip(startDate: .now, isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)
        let before = Date.now
        service.startRecording(trip: trip, source: .automatic)
        let after = Date.now

        await service.checkWatchdog(now: after.addingTimeInterval(3600))

        let end = try XCTUnwrap(trip.endDate)
        XCTAssertGreaterThanOrEqual(end, before)
        XCTAssertLessThanOrEqual(end, after)
        XCTAssertNil(try TripRepository(context: context).activeTrip())
    }

    func testWatchdogCheckLeavesRecentTripAlone() async throws {
        let context = try makeContext()
        let service = LocationTrackingService()
        service.configure(context: context)

        let trip = Trip(startDate: .now, isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .automatic)

        await service.checkWatchdog(now: .now.addingTimeInterval(30))

        XCTAssertNil(trip.endDate)
    }

    private func location(offset: TimeInterval, from start: Date, latitude: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 5.0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 0, speed: 10, timestamp: start.addingTimeInterval(offset)
        )
    }

    /// Als de app tijdens een rit gekilld wordt, moet de database nog weten
    /// wanneer het laatste teken van leven was; anders valt herstel terug op
    /// de ritstart en gaat de route verloren.
    func testRoutePersistedWhileTripIsStillRecording() async throws {
        let context = try makeContext()
        let service = LocationTrackingService()
        service.configure(context: context)

        let start = Date.now
        let trip = Trip(startDate: start, isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .automatic)

        service.handle(locations: [
            location(offset: 5, from: start, latitude: 52.0000),
            location(offset: 70, from: start, latitude: 52.0100),
        ])

        XCTAssertNil(trip.endDate, "rit loopt nog")
        let data = try XCTUnwrap(trip.routeData)
        let points = try RoutePolyline.decode(data)
        XCTAssertEqual(points.last?.offset ?? 0, 70, accuracy: 0.001)
    }

    func testRouteIsNotWrittenForEverySample() async throws {
        let context = try makeContext()
        let service = LocationTrackingService()
        service.configure(context: context)

        let start = Date.now
        let trip = Trip(startDate: start, isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .automatic)

        service.handle(locations: [location(offset: 5, from: start, latitude: 52.0000)])
        service.handle(locations: [location(offset: 15, from: start, latitude: 52.0010)])

        let points = try RoutePolyline.decode(try XCTUnwrap(trip.routeData))
        XCTAssertEqual(points.count, 1, "tweede sample komt binnen de interval en wacht op de volgende schrijfbeurt")
    }

    func testWatchdogCheckKeepsManualRecordingDuringLongStop() async throws {
        let context = try makeContext()
        let service = LocationTrackingService()
        service.configure(context: context)

        let trip = Trip(startDate: .now)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .manual)

        await service.checkWatchdog(now: .now.addingTimeInterval(3600))

        XCTAssertEqual(service.recordingSource, .manual, "handmatige opname blijft doorlopen tot STOP")
    }

    // MARK: - Geïnjecteerde providers

    func testServiceUsesInjectedLocationProviderForRecording() async throws {
        let context = try makeContext()
        let provider = FakeLocationProvider()
        let service = LocationTrackingService(locationProvider: provider)
        service.configure(context: context)

        let trip = Trip(startDate: .now)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .manual)

        XCTAssertTrue(provider.isUpdating)
        XCTAssertTrue(provider.backgroundAllowed)

        await service.stopRecording(endDate: .now)
        XCTAssertFalse(provider.isUpdating)
        XCTAssertFalse(provider.backgroundAllowed)
    }

    func testRevokedPermissionDuringRecordingShowsIssueAndStops() async throws {
        let context = try makeContext()
        let provider = FakeLocationProvider()
        let service = LocationTrackingService(locationProvider: provider)
        service.configure(context: context)

        let trip = Trip(startDate: .now, isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .automatic)

        provider.changeAuthorization(to: .denied)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(service.currentIssue, .permissionRevokedDuringRecording)
        XCTAssertNil(service.recordingSource)
    }

    func testLocationsFromProviderReachTheRoute() async throws {
        let context = try makeContext()
        let provider = FakeLocationProvider()
        let service = LocationTrackingService(locationProvider: provider)
        service.configure(context: context)

        let start = Date.now
        let trip = Trip(startDate: start)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .manual)

        provider.deliver([location(offset: 5, from: start, latitude: 52.0)])

        XCTAssertNotNil(trip.routeData, "eerste punt wordt direct tussentijds weggeschreven")
    }

    func testWatchdogRunsOnInjectedClockAndClosesTripAfterSilence() async throws {
        let context = try makeContext()
        let clock = VirtualClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let service = LocationTrackingService(
            locationProvider: FakeLocationProvider(),
            motionProvider: FakeMotionProvider(),
            time: clock,
            geocoder: FakeAddressResolver()
        )
        service.configure(context: context)

        let trip = Trip(startDate: clock.now, isAutomaticallyRecorded: true)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .automatic)

        // Standaard drempel 180 s + 60 s marge, timer elke 30 s.
        await clock.advance(to: clock.now.addingTimeInterval(300))

        XCTAssertNotNil(trip.endDate)
        XCTAssertNil(service.recordingSource)
    }

    // I1 (review): locaties komen soms in één batch binnen. Het eerste sample na een
    // gat beëindigt de rit; de volgende samples in dezelfde batch horen bij een
    // nieuwe rit en niet bij de oude.
    func testBatchAfterGapEndsOldTripAndStartsNewOne() async throws {
        let context = try makeContext()
        let provider = FakeLocationProvider()
        let clock = VirtualClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let service = LocationTrackingService(
            locationProvider: provider, motionProvider: FakeMotionProvider(),
            time: clock, geocoder: FakeAddressResolver()
        )
        service.configure(context: context)
        let settings = AppSettings.fetchOrCreate(in: context)
        settings.trackingMode = .automatic
        settings.autoStopThresholdMinutes = 3
        service.applySettings(settings)

        func fix(_ seconds: TimeInterval, _ meters: Double) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 52.0 + meters / 111_320, longitude: 5.0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: 14,
                timestamp: clock.now.addingTimeInterval(seconds)
            )
        }
        // Eerste rit start en loopt een tijd.
        provider.deliver([fix(0, 0)])
        provider.deliver([fix(2, 28)])
        provider.deliver([fix(4, 56)])
        // Na 25 minuten (gat) komt één batch met drie samples.
        provider.deliver([fix(1500, 20_000), fix(1502, 20_028), fix(1504, 20_056)])
        for _ in 0..<30 { await Task.yield() }

        let trips = try TripRepository(context: context).trips().sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(trips.count, 2, "tweede rit wordt niet geblokkeerd")
        XCTAssertLessThan(trips[0].distanceKm, 0.5, "de 20 km over het gat horen niet bij de eerste rit")
        XCTAssertEqual(service.recordingSource, .automatic, "de tweede rit wordt opgenomen")
    }

    // I3 (review): of iOS gepauzeerde updates zelf hervat is niet bewezen (A4). Bij het
    // actief worden van de app starten we de updates daarom opnieuw (idempotent).
    func testAppDidBecomeActiveRestartsUpdatesWhileRecording() async throws {
        let context = try makeContext()
        let provider = FakeLocationProvider()
        let service = LocationTrackingService(locationProvider: provider)
        service.configure(context: context)

        let trip = Trip(startDate: .now)
        try TripWriteService(context: context).create(trip)
        service.startRecording(trip: trip, source: .manual)
        let before = provider.calls.filter { $0 == "startUpdating" }.count

        await service.appDidBecomeActive()

        XCTAssertEqual(provider.calls.filter { $0 == "startUpdating" }.count, before + 1)
    }
}
