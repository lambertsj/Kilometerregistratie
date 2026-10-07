import CoreLocation
import SwiftData
import XCTest
@testable import Kilometerregistratie

enum ScenarioMode {
    case manual, hybrid, automatic

    var trackingMode: TrackingMode {
        switch self {
        case .manual: .manual
        case .hybrid: .hybrid
        case .automatic: .automatic
        }
    }
}

/// Speelt scenario's af op virtuele tijd. De wereld (positie, tijd) leeft hier;
/// `FakeIOS` beslist wat de service ervan te zien krijgt.
@MainActor
final class ScenarioRunner {
    let clock: VirtualClock
    let ios: FakeIOS
    let context: ModelContext
    private(set) var service: LocationTrackingService
    let stopAfterMinutes: Int
    let mode: ScenarioMode

    private let container: ModelContainer
    private let location = FakeLocationProvider()
    private let motion = FakeMotionProvider()
    private let tick: TimeInterval = 1

    // Wereld
    private var latitude = 52.0
    private var longitude = 5.0
    private let metersPerDegreeLatitude = 111_320.0

    // Waarheid voor invarianten
    private(set) var truthMovementTimes: [Date] = []
    /// Totaal verplaatst (rijden plus onzichtbare sprongen); bovengrens voor wat geregistreerd mag zijn.
    private(set) var truthDrivenMeters = 0.0
    /// Momenten waarop de gebruiker op STOP tikte; een einddatum die daarmee
    /// samenvalt is een keuze van de gebruiker en geen automatisch einde.
    private(set) var userStopDates: Set<Date> = []

    init(mode: ScenarioMode, stopAfterMinutes: Int = 3, ios params: IOSParameters = IOSParameters()) throws {
        self.mode = mode
        self.stopAfterMinutes = stopAfterMinutes
        let container = try ModelContainer(
            for: AppSchema.schema,
            configurations: [ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)]
        )
        self.container = container
        let context = ModelContext(container)
        self.context = context
        let clock = VirtualClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        self.clock = clock
        ios = FakeIOS(params: params, location: location, clock: clock)
        service = LocationTrackingService(
            locationProvider: location, motionProvider: motion, time: clock, geocoder: FakeAddressResolver()
        )

        let settings = AppSettings.fetchOrCreate(in: context)
        settings.trackingMode = mode.trackingMode
        settings.autoStopThresholdMinutes = stopAfterMinutes
        try context.save()

        service.configure(context: context)
        service.applySettings(settings)

        ios.onRelaunch = { [weak self] in await self?.launchService() }
        ios.onBecameActive = { [weak self] in await self?.service.appDidBecomeActive() }
    }

    // MARK: - Uitkomst

    var trips: [Trip] {
        ((try? TripRepository(context: context).trips()) ?? []).sorted { $0.startDate < $1.startDate }
    }

    var openTrips: [Trip] { trips.filter { $0.endDate == nil } }

    // MARK: - Wereld

    func drive(meters: Double, speed: Double = 14, accuracy: Double = 5, speedKnown: Bool = true) async {
        let seconds = Int((meters / speed).rounded())
        for _ in 0..<max(seconds, 1) {
            await advance(by: tick)
            latitude += speed * tick / metersPerDegreeLatitude
            truthDrivenMeters += speed * tick
            if speed >= 1.4 { truthMovementTimes.append(clock.now) }
            await offerFix(speed: speedKnown ? speed : -1, accuracy: accuracy)
        }
    }

    /// Stilstaan; fixes worden elke 10 s aangeboden (iOS filtert ze toch weg).
    func stand(for seconds: TimeInterval) async {
        var remaining = seconds
        while remaining > 0 {
            let step = min(10, remaining)
            await advance(by: step)
            await offerFix(speed: 0, accuracy: 5)
            remaining -= step
        }
    }

    /// Verplaatsen zonder dat er fixes zijn (tunnel, GPS-gat). De afstand telt
    /// niet mee als "gereden en geregistreerd".
    func jump(meters: Double, over seconds: TimeInterval) async {
        await advance(by: seconds)
        latitude += meters / metersPerDegreeLatitude
        // Echt verplaatst, alleen niet gezien: een lopende opname mag die
        // afstand meetellen (bv. een handmatige rit door een tunnel).
        truthDrivenMeters += meters
    }

    /// Tijd laten lopen zonder fixes.
    func wait(for seconds: TimeInterval) async {
        var remaining = seconds
        while remaining > 0 {
            let step = min(30, remaining)
            await advance(by: step)
            remaining -= step
        }
    }

    // MARK: - App

    func appToBackground() { ios.goToBackground() }
    func appSuspend() { ios.suspend() }
    func appResume() async { await ios.resume(); await settle() }

    func appKill() {
        ios.terminate()
        location.resetForNewProcess()
        motion.resetForNewProcess()
    }

    /// Gebruiker opent de app weer na een kill.
    func appRelaunch() async {
        await ios.relaunchByUser()
        await settle()
    }

    func revokePermission() async {
        location.changeAuthorization(to: .denied)
        await settle()
        if ios.params.revokingPermissionTerminatesApp { appKill() }
    }

    /// Nieuw proces: nieuwe service op dezelfde database, zoals de app het doet.
    private func launchService() async {
        clock.removeAllTimers()
        location.resetForNewProcess()
        motion.resetForNewProcess()
        service = LocationTrackingService(
            locationProvider: location, motionProvider: motion, time: clock, geocoder: FakeAddressResolver()
        )
        service.configure(context: context)
        service.applySettings(AppSettings.fetchOrCreate(in: context))
        await service.resumeIfNeeded(context: context, now: clock.now)
    }

    // MARK: - Gebruiker

    /// Gedraagt zich als `HomeView.toggleRecording` bij START.
    func userTapsStart() async throws {
        await userOpensApp()
        let recorder = TripRecorder(now: { [clock] in clock.now })
        if let trip = try recorder.start(context: context, vehicle: nil) {
            service.beginRouteRecording(for: trip)
        }
    }

    /// Gedraagt zich als `HomeView.toggleRecording` bij STOP.
    func userTapsStop() async throws {
        await userOpensApp()
        userStopDates.insert(clock.now)
        await service.stopRecording(endDate: clock.now)
        try TripRecorder(now: { [clock] in clock.now }).stop(context: context)
        await settle()
    }

    /// Een gebruiker kan alleen tikken in een draaiende app: na een kill of
    /// opschorten opent hij die eerst.
    private func userOpensApp() async {
        switch ios.appState {
        case .terminated: await appRelaunch()
        case .suspended, .background: await appResume()
        case .foreground: break
        }
    }

    // MARK: - Intern

    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func advance(by seconds: TimeInterval) async {
        await clock.advance(to: clock.now.addingTimeInterval(seconds))
        await settle()
    }

    private func offerFix(speed: Double, accuracy: Double) async {
        await ios.offer(FakeIOS.Fix(
            latitude: latitude, longitude: longitude, speed: speed, accuracy: accuracy, timestamp: clock.now
        ))
        await settle()
    }
}
