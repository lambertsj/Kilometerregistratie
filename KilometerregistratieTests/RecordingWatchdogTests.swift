import XCTest
@testable import Kilometerregistratie

final class RecordingWatchdogTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testDoesNotStopWhileSamplesKeepArriving() {
        let watchdog = RecordingWatchdog(stopAfterStationaryInterval: 180)
        XCTAssertFalse(watchdog.shouldForceStop(
            recordingStartedAt: start,
            lastSampleAt: start.addingTimeInterval(100),
            now: start.addingTimeInterval(110)
        ))
    }

    func testStopsWhenGPSStopsDeliveringSamplesEntirely() {
        // Scenario uit FASE 1.1: iOS pauzeert locatie-updates volledig (of de
        // achtergrondlimiet is bereikt) en er komt geen enkel sample meer
        // binnen. TripDetector kan dit niet zelf zien; de watchdog wel.
        let watchdog = RecordingWatchdog(stopAfterStationaryInterval: 180)
        let lastSample = start.addingTimeInterval(100)
        XCTAssertFalse(watchdog.shouldForceStop(
            recordingStartedAt: start,
            lastSampleAt: lastSample,
            now: lastSample.addingTimeInterval(180 + 59)
        ))
        XCTAssertTrue(watchdog.shouldForceStop(
            recordingStartedAt: start,
            lastSampleAt: lastSample,
            now: lastSample.addingTimeInterval(180 + 60)
        ))
    }

    func testStopsAtMaxTripDurationEvenWithFreshSamples() {
        let watchdog = RecordingWatchdog(stopAfterStationaryInterval: 180, maxTripDuration: 3600)
        let now = start.addingTimeInterval(3600)
        XCTAssertTrue(watchdog.shouldForceStop(recordingStartedAt: start, lastSampleAt: now, now: now))
    }

    /// Een handmatige rit eindigt door STOP, niet door stilte: wie vijf minuten
    /// bij een klant staat of in de file, mag geen route kwijtraken.
    func testIgnoringGPSSilenceKeepsManualRecordingAlive() {
        let watchdog = RecordingWatchdog(stopAfterStationaryInterval: 180)
        XCTAssertFalse(watchdog.shouldForceStop(
            recordingStartedAt: start,
            lastSampleAt: start.addingTimeInterval(100),
            now: start.addingTimeInterval(100 + 3600),
            ignoreGPSSilence: true
        ))
    }

    func testIgnoringGPSSilenceStillEnforcesMaxTripDuration() {
        let watchdog = RecordingWatchdog(stopAfterStationaryInterval: 180, maxTripDuration: 3600)
        XCTAssertTrue(watchdog.shouldForceStop(
            recordingStartedAt: start,
            lastSampleAt: start.addingTimeInterval(3000),
            now: start.addingTimeInterval(3600),
            ignoreGPSSilence: true
        ))
    }
}
