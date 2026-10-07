import XCTest
import SwiftData
@testable import Kilometerregistratie

/// Scenario's over tijd. Elke test noemt de iOS-aannames (docs/ios-assumptions.md)
/// waarop hij leunt.
@MainActor
final class ScenarioTests: XCTestCase {

    /// Gewone woon-werkrit, app blijft actief. Leunt op: A1.
    func testCommuteWithAppActiveEndsAutomatically() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 12_000)          // ~14 min
        await s.stand(for: 15 * 60)

        XCTAssertEqual(s.trips.count, 1)
        XCTAssertEqual(s.openTrips.count, 0)
        XCTAssertGreaterThan(try XCTUnwrap(s.trips.first).distanceKm, 11)
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    /// Telefoon in de zak: iOS pauzeert de GPS (A2) en schort de app op (A3).
    /// Zonder open van de app blijft de rit staan; dit is de bekende beperking
    /// die alleen een toestel kan oplossen (echte wake-up, A4).
    func testSuspendedAppKeepsTripOpenUntilUserOpensApp() async throws {
        var ios = IOSParameters()
        ios.autoPauseAfter = 120          // korter dan de watchdog (240 s)
        let s = try ScenarioRunner(mode: .automatic, ios: ios)
        s.appToBackground()
        await s.drive(meters: 8_000)
        await s.stand(for: 30 * 60)       // geparkeerd; app wordt opgeschort

        XCTAssertEqual(s.ios.appState, .suspended)
        XCTAssertEqual(s.openTrips.count, 1, "opgeschorte app kan zichzelf niet afsluiten")

        await s.appResume()               // gebruiker opent de app (appDidBecomeActive)

        XCTAssertEqual(s.openTrips.count, 0)
        XCTAssertEqual(s.trips.count, 1)
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    /// App gekild tijdens een rit, snel weer geopend: rit wordt hervat met de
    /// route die tussentijds was weggeschreven. Leunt op: A6.
    func testKillDuringTripThenQuickRelaunchResumesWithRoute() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 5_000)
        s.appKill()
        await s.wait(for: 5 * 60)
        await s.appRelaunch()

        let trip = try XCTUnwrap(s.openTrips.first, "rit wordt hervat")
        let route = try RoutePolyline.decode(try XCTUnwrap(trip.routeData))
        XCTAssertGreaterThan(route.count, 10, "route bleef behouden over de kill")

        await s.stand(for: 15 * 60)
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }
}
