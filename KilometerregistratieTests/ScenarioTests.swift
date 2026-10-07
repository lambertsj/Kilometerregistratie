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

    // Geval 1 en 2: handmatig START, niet op STOP. De rit blijft bewust open; de
    // opname blijft doorlopen (geen watchdog-stop op stilte). Leunt op: A1.
    func testManualTripStaysOpenAndRecordingContinuesDuringLongStop() async throws {
        let s = try ScenarioRunner(mode: .manual)
        try await s.userTapsStart()
        await s.drive(meters: 3_000)
        await s.stand(for: 20 * 60)            // lang bij een klant

        XCTAssertEqual(s.service.recordingSource, .manual, "geval 2: opname loopt door")
        await s.drive(meters: 3_000)           // en rijdt weer verder

        try await s.userTapsStop()
        let trip = try XCTUnwrap(s.trips.first)
        XCTAssertNotNil(trip.endDate)
        XCTAssertGreaterThan(trip.distanceKm, 5.5, "ook het stuk ná de lange stop is opgenomen")
        try s.assertInvariants()
    }

    // Geval 3: app op de voorgrond, rit sluit zichzelf af en het scherm ziet dat.
    func testAutomaticTripClosedWhileAppIsInForeground() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 6_000)
        await s.stand(for: 10 * 60)

        XCTAssertNil(s.service.recordingSource)
        XCTAssertEqual(s.openTrips.count, 0)
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    // Geval 6a: na een GPS-gat meteen weer rijsnelheid, app actief. De watchdog
    // sluit de rit tijdens het gat; het gat telt niet als rijtijd of afstand.
    func testFastSampleAfterLongGapStartsNewTripInsteadOfExtendingOldOne() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 5_000)
        await s.jump(meters: 20_000, over: 25 * 60)   // tunnel/gat zonder fixes
        await s.drive(meters: 5_000)
        await s.stand(for: 15 * 60)

        XCTAssertEqual(s.trips.count, 2)
        let km = s.trips.map(\.distanceKm).reduce(0, +)
        XCTAssertLessThan(km, 11, "de 20 km over het gat tellen niet mee")
        try s.assertInvariants()
    }

    // Geval 6b: dezelfde situatie, maar de app is opgeschort, dus de watchdog
    // draait niet en alleen de detector kan het gat zien. Leunt op: A3, A4.
    // NB: de volgorde "timers hervatten, dan het sample afleveren" bij het
    // wakker worden is zelf een aanname (FakeIOS, `.suspended`); de uitkomst
    // moet in beide volgordes twee ritten zijn.
    func testSuspendedGapThenMovementDoesNotCountGapAsDistance() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        s.appToBackground()
        await s.drive(meters: 5_000)
        s.appSuspend()
        await s.jump(meters: 20_000, over: 25 * 60)
        await s.drive(meters: 5_000)            // beweging maakt de app wakker (A4)
        await s.stand(for: 15 * 60)
        await s.appResume()

        XCTAssertEqual(s.trips.count, 2)
        let km = s.trips.map(\.distanceKm).reduce(0, +)
        XCTAssertLessThan(km, 11, "de 20 km over het gat tellen niet mee")
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    // Geval 6c: als het eerste sample na het wakker worden vóór de timers komt
    // (A11), kan alleen de detector het gat zien. Zonder de gat-controle in
    // TripDetector loopt de rit door en telt het gat als afstand en rijtijd.
    func testDetectorEndsTripOnGapWhenSampleArrivesBeforeTimers() async throws {
        var ios = IOSParameters()
        ios.timersResumeBeforeFirstSample = false
        let s = try ScenarioRunner(mode: .automatic, ios: ios)
        s.appToBackground()
        await s.drive(meters: 5_000)
        s.appSuspend()
        await s.jump(meters: 20_000, over: 25 * 60)
        await s.drive(meters: 5_000)
        await s.stand(for: 15 * 60)
        await s.appResume()

        XCTAssertEqual(s.trips.count, 2)
        let km = s.trips.map(\.distanceKm).reduce(0, +)
        XCTAssertLessThan(km, 11, "de 20 km over het gat tellen niet mee")
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    // Geval 7: hybride, handmatige rit; er komt geen tweede (automatische) rit
    // naast en na STOP staat er niets open. Leunt op: A1.
    func testHybridManualTripIsNotDuplicatedByDetection() async throws {
        let s = try ScenarioRunner(mode: .hybrid)
        try await s.userTapsStart()
        await s.drive(meters: 8_000)
        try await s.userTapsStop()
        await s.stand(for: 10 * 60)

        XCTAssertEqual(s.trips.count, 1)
        XCTAssertEqual(s.openTrips.count, 0)
        try s.assertInvariants()
    }

    // Geval 8: een rit sluit af en daarna begint een nieuwe automatisch (niet geblokkeerd).
    func testSecondTripAfterFirstIsRegistered() async throws {
        let s = try ScenarioRunner(mode: .automatic, stopAfterMinutes: 3)
        await s.drive(meters: 6_000)
        await s.stand(for: 40 * 60)             // ver voorbij de merge-grens
        await s.drive(meters: 6_000)
        await s.stand(for: 15 * 60)

        XCTAssertEqual(s.trips.count, 2)
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    // Geval 9: kill en pas na meer dan 30 minuten heropend: rit wordt afgesloten
    // op het laatste teken van leven, nooit op duur nul. Leunt op: A6.
    func testKillThenLateRelaunchFinalizesAtLastKnownActivity() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 12_000)
        let lastDriving = s.clock.now
        s.appKill()
        await s.wait(for: 90 * 60)
        await s.appRelaunch()

        let trip = try XCTUnwrap(s.trips.first)
        let end = try XCTUnwrap(trip.endDate, "rit is afgesloten")
        XCTAssertGreaterThan(end.timeIntervalSince(trip.startDate), 10 * 60, "niet op duur nul")
        XCTAssertLessThanOrEqual(abs(end.timeIntervalSince(lastDriving)), 120)
        try s.assertInvariants()
    }

    // Geval 12: toestemming ingetrokken tijdens de rit. iOS beëindigt de app (A9);
    // na heropenen staat er geen rit open.
    func testPermissionRevokedDuringTripLeavesNoOpenTrip() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 5_000)
        await s.revokePermission()
        await s.wait(for: 60 * 60)
        await s.appRelaunch()

        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    // Geval 12b (gevonden door de fuzz-test, seed 26): toestemming ingetrokken
    // en de app wordt binnen 30 minuten weer geopend. Zonder toestemming kan de
    // opname niet hervat worden; de rit moet dan afgesloten worden op het
    // laatste teken van leven in plaats van voor altijd open te blijven.
    func testRelaunchWithoutPermissionWithinResumeWindowFinalizesTrip() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 5_000)
        s.appKill()                             // eerst gekild: de service kan zelf niets meer afsluiten
        await s.revokePermission()              // toestemming verdwijnt terwijl de app niet draait
        await s.wait(for: 5 * 60)               // korter dan de hervat-grens van 30 min
        await s.appRelaunch()
        await s.wait(for: 5 * 60)

        XCTAssertEqual(s.openTrips.count, 0, "rit blijft niet open staan zonder toestemming")
        XCTAssertNotNil(s.trips.first?.endDate)
        try s.assertInvariants()
    }

    // Geval 10: zonder detectie (handmatige modus) start een beëindigde app niet
    // door een significante wijziging; er ontstaat dus geen rit. Leunt op: A5.
    func testWithoutDetectionAKilledAppRegistersNothing() async throws {
        let s = try ScenarioRunner(mode: .manual)
        s.appKill()
        await s.drive(meters: 5_000)
        await s.appRelaunch()

        XCTAssertEqual(s.trips.count, 0)
        try s.assertInvariants()
    }

    // Geval 11: onbekende snelheid (-1) tijdens de rit; rit wordt niet afgekapt.
    // Leunt op: A7.
    func testUnknownSpeedDuringTripDoesNotEndTripEarly() async throws {
        let s = try ScenarioRunner(mode: .automatic, stopAfterMinutes: 3)
        await s.drive(meters: 1_000)                                    // start gedetecteerd
        await s.drive(meters: 9_000, speedKnown: false)                 // ruim > 3 min zonder snelheid
        await s.drive(meters: 1_000)
        await s.stand(for: 10 * 60)

        XCTAssertEqual(s.trips.count, 1, "één doorlopende rit")
        XCTAssertGreaterThan(try XCTUnwrap(s.trips.first).distanceKm, 10)
        try s.assertInvariants()
    }

    // Geval 13: detectie uitzetten tijdens een automatische rit sluit hem af.
    func testSwitchingToManualDuringAutomaticTripClosesIt() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 5_000)

        let settings = AppSettings.fetchOrCreate(in: s.context)
        settings.trackingMode = .manual
        s.service.applySettings(settings)
        await s.settle()

        XCTAssertEqual(s.openTrips.count, 0)
        XCTAssertNotNil(s.trips.first?.endDate)
        try s.assertInvariants()
    }

    // I2 (review): een rit die na een kill wordt afgesloten op het laatste teken van
    // leven houdt zijn afstand, coördinaten en adressen; hij staat niet als 0 km.
    func testFinalizedTripAfterLateRelaunchKeepsDistanceAndAddresses() async throws {
        let s = try ScenarioRunner(mode: .automatic)
        await s.drive(meters: 12_000)
        s.appKill()
        await s.wait(for: 90 * 60)
        await s.appRelaunch()

        let trip = try XCTUnwrap(s.trips.first)
        XCTAssertGreaterThan(trip.distanceKm, 10, "afstand uit de opgeslagen route")
        XCTAssertNotNil(trip.endLatitude)
        XCTAssertNotNil(trip.endAddress)
        try s.assertInvariants()
    }

    // I4 (review): na STOP van een handmatige rit in hybride modus moet de detector
    // weer schoon beginnen; doorrijden start dan een automatische rit.
    func testHybridDrivingOnAfterManualStopStartsAutomaticTrip() async throws {
        let s = try ScenarioRunner(mode: .hybrid)
        try await s.userTapsStart()
        await s.drive(meters: 5_000)
        try await s.userTapsStop()
        await s.drive(meters: 6_000)            // privé verder gereden
        await s.stand(for: 15 * 60)

        XCTAssertEqual(s.trips.count, 2, "handmatige rit plus een automatische rit")
        XCTAssertEqual(s.trips.filter(\.isAutomaticallyRecorded).count, 1)
        s.assertNoOpenAutomaticTrip()
        try s.assertInvariants()
    }

    // C1 (review): een handmatige rit zonder route (toestemming geweigerd) wordt na
    // een kill niet op duur nul afgesloten; STOP blijft bereikbaar.
    func testManualTripWithoutRouteStaysOpenAfterKill() async throws {
        let s = try ScenarioRunner(mode: .manual)
        await s.denyPermission()
        try await s.userTapsStart()
        await s.wait(for: 10 * 60)
        s.appKill()
        await s.wait(for: 5 * 60)
        await s.appRelaunch()

        let trip = try XCTUnwrap(s.trips.first)
        XCTAssertNil(trip.endDate, "de gebruiker sluit zelf af met STOP")
        try await s.userTapsStop()
        let ended = try XCTUnwrap(s.trips.first?.endDate)
        XCTAssertGreaterThan(ended.timeIntervalSince(trip.startDate), 10 * 60)
        try s.assertInvariants()
    }

    // I6 (review): in een regio met bewaarplicht (Duitsland) geeft het afsluiten van
    // een automatische rit geen revisies; adressen en categorie horen bij het vastleggen.
    func testAutomaticTripInGermanyProducesNoUpdateRevisions() async throws {
        let s = try ScenarioRunner(mode: .automatic, region: .germany)
        await s.drive(meters: 8_000)
        await s.stand(for: 15 * 60)

        XCTAssertEqual(s.trips.count, 1)
        XCTAssertNotNil(s.trips.first?.endAddress)
        XCTAssertEqual(s.updatedRevisionCount, 0, "afsluiten is vastleggen, geen wijziging achteraf")
        try s.assertInvariants()
    }
}
