import CoreLocation
import Foundation
@testable import Kilometerregistratie

/// Model van iOS-gedrag rond locatie en levenscyclus. Elke regel verwijst naar
/// een aanname in docs/ios-assumptions.md en heeft een instelbare waarde.
struct IOSParameters {
    /// A2: na zoveel seconden stilstand pauzeert iOS de updates en schort de
    /// app op (als hij op de achtergrond staat).
    var autoPauseAfter: TimeInterval = 600
    /// A5: afstand die een significante wijziging triggert.
    var significantChangeDistance: Double = 500
    /// A4: hervatte updates maken een opgeschorte app wakker.
    var wakesWhenUpdatesResume = true
    /// A9: toestemming intrekken beëindigt de app.
    var revokingPermissionTerminatesApp = true
}

enum AppState: Equatable {
    case foreground, background, suspended, terminated
}

@MainActor
final class FakeIOS {
    struct Fix {
        var latitude: Double
        var longitude: Double
        var speed: Double
        var accuracy: Double
        var timestamp: Date
    }

    var params: IOSParameters
    private(set) var appState: AppState = .foreground
    /// Wordt aangeroepen als iOS een beëindigde app opnieuw start (A5).
    var onRelaunch: (() async -> Void)?
    /// Wordt aangeroepen als de app weer actief wordt (voorgrond).
    var onBecameActive: (() async -> Void)?

    private let location: FakeLocationProvider
    private let clock: VirtualClock

    /// Positie waarop de laatste "beweging" (>= distanceFilter) plaatsvond.
    private var anchor: (lat: Double, lon: Double)?
    private var lastMovementAt: Date?
    /// Positie van de laatste significante-wijziging-levering.
    private var significantAnchor: (lat: Double, lon: Double)?

    init(params: IOSParameters, location: FakeLocationProvider, clock: VirtualClock) {
        self.params = params
        self.location = location
        self.clock = clock
    }

    // MARK: - Levenscyclus

    func goToBackground() {
        if appState == .foreground { appState = .background }
    }

    /// A3: een opgeschorte app voert niets meer uit, ook geen timers.
    func suspend() {
        guard appState == .background || appState == .foreground else { return }
        appState = .suspended
        clock.timersEnabled = false
    }

    func resume() async {
        guard appState != .terminated else { return }
        appState = .foreground
        await clock.resumeTimers()
        await onBecameActive?()
    }

    /// A6: het proces is weg; geheugen verloren, database blijft.
    func terminate() {
        appState = .terminated
        clock.timersEnabled = false
        clock.removeAllTimers()
    }

    /// De gebruiker opent een beëindigde app zelf weer.
    func relaunchByUser() async {
        guard appState == .terminated else { return }
        await relaunchInBackground()
        await resume()
    }

    /// A5: iOS start de app op de achtergrond opnieuw.
    private func relaunchInBackground() async {
        appState = .background
        clock.timersEnabled = true
        await onRelaunch?()
    }

    // MARK: - Levering van fixes

    func offer(_ fix: Fix) async {
        let position = (lat: fix.latitude, lon: fix.longitude)
        let moved = anchor.map { distance($0, position) } ?? .infinity
        let isMoving = moved >= location.distanceFilter
        if isMoving {
            anchor = position
            lastMovementAt = fix.timestamp
        }

        switch appState {
        case .terminated:
            // Alleen een actief abonnement op significante wijzigingen start de
            // app opnieuw (handmatige modus heeft dat niet).
            guard location.isMonitoringSignificantChanges, significantDue(position) else { return }
            significantAnchor = position
            await relaunchInBackground()
            deliver(fix)

        case .suspended:
            // A4/A5: alleen beweging maakt een opgeschorte app wakker.
            let wakesByUpdates = location.isUpdating && params.wakesWhenUpdatesResume && isMoving
            let wakesBySignificant = location.isMonitoringSignificantChanges && significantDue(position)
            guard wakesByUpdates || wakesBySignificant else { return }
            if wakesBySignificant { significantAnchor = position }
            appState = .background
            clock.timersEnabled = true
            await clock.resumeTimers()
            deliver(fix)

        case .foreground, .background:
            if location.isUpdating {
                if isMoving {
                    deliver(fix)
                } else if appState == .background,
                          let last = lastMovementAt,
                          fix.timestamp.timeIntervalSince(last) >= params.autoPauseAfter {
                    // A2 + A3: iOS pauzeert de updates; de app wordt opgeschort.
                    suspend()
                }
            } else if location.isMonitoringSignificantChanges, significantDue(position) {
                significantAnchor = position
                deliver(fix)
            }
        }
    }

    private func deliver(_ fix: Fix) {
        let clLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
            altitude: 0,
            horizontalAccuracy: fix.accuracy,
            verticalAccuracy: fix.accuracy,
            course: 0,
            speed: fix.speed,
            timestamp: fix.timestamp
        )
        location.deliver([clLocation])
    }

    private func significantDue(_ position: (lat: Double, lon: Double)) -> Bool {
        guard let anchor = significantAnchor else { return true }
        return distance(anchor, position) >= params.significantChangeDistance
    }

    private func distance(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        GeoDistance.meters(fromLatitude: a.lat, longitude: a.lon, toLatitude: b.lat, longitude: b.lon)
    }
}
