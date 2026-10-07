# Ritdetectie-simulatie Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scenario's voor automatische ritdetectie (rijden, stilstaan, GPS-pauze, opschorten, kill, herstel, toestemming) reproduceerbaar en geautomatiseerd testen zonder toestel, met een expliciet vastgelegd iOS-model.

**Architecture:** `LocationTrackingService` krijgt vier geïnjecteerde protocollen (`LocationProviding`, `MotionProviding`, `AddressResolving`, `TimeSource`) met echte adapters als standaard. In de tests sturen een `VirtualClock`, nagebootste providers en een `FakeIOS` (levenscyclus + leveringsregels) de service aan via een `ScenarioRunner`; invarianten en een seed-gestuurde fuzz-test bewaken de uitkomst in de database.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, CoreLocation, CoreMotion, XCTest, `xcodebuild`. iOS 17+. Het project compileert met `-warnings-as-errors`.

**Spec:** `docs/superpowers/specs/2026-10-07-ritdetectie-simulatie-design.md`

## Global Constraints

- Alle protocollen en fakes zijn `@MainActor`.
- Alle commentaar, testnamen en gebruikersgerichte tekst in het Nederlands, zoals in de rest van de code.
- De app mag voor de gebruiker niet veranderen; de bestaande 79 tests moeten onveranderd groen blijven na elke taak.
- Bestaande publieke gedrag blijft: `LocationTrackingService()` zonder argumenten werkt nog.
- Nieuwe bestanden moeten in `Kilometerregistratie.xcodeproj/project.pbxproj` staan (het project gebruikt geen automatische mappen). Gebruik `scripts/add_to_xcodeproj.py` uit Taak 1.
- Autoritatieve tolerantie: gereden afstand wordt nooit méér dan 3% + 100 m overschat. Einddatum van een automatische rit ligt hooguit drempel + 60 s + 30 s + 1 s na het laatste beweegmoment.
- Testopdracht (overal hieronder `TEST`):
  `xcodebuild test -project Kilometerregistratie.xcodeproj -scheme Kilometerregistratie -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  Met een filter: voeg `-only-testing:KilometerregistratieTests/<Klasse>` toe. Filter de uitvoer met
  `2>&1 | grep -E "error:|Executed .* tests|TEST (SUCCEEDED|FAILED)"`.

## Review Focus

- Een rit die open blijft staan nadat de app is opgeschort en nooit meer geopend wordt: moet als bekende beperking getest en benoemd zijn (niet stil weggelaten).
- Handmatige rit in hybride modus terwijl detectie een eigen rit zou starten: geen dubbele ritten en geen open rit na STOP.
- Kill tijdens een rit en herstel binnen en na 30 minuten: route blijft behouden of de rit wordt netjes afgesloten, nooit op duur nul.
- Toestemming ingetrokken tijdens een lopende rit (app wordt beëindigd, A9): na herstart geen open rit.
- Een gat in de samples met rijsnelheid erna: de afstand over het gat telt niet mee.

---

## File Structure

Productiecode (`Kilometerregistratie/Services/Platform/`):
- `TimeSource.swift`: `TimeSource`, `TimerHandle`, `SystemTimeSource`.
- `LocationProviding.swift`: `LocationProviding`, `LocationProvidingDelegate`.
- `CoreLocationProvider.swift`: echte adapter.
- `MotionProviding.swift`: `MotionProviding` + `CoreMotionProvider`.
- `AddressResolving.swift`: protocol + conformance van `GeocodingService`.

Wijzigingen: `Services/LocationTrackingService.swift`, `Services/TripRecorder.swift`, `App/KilometerregistratieApp.swift`.

Testgereedschap (`KilometerregistratieTests/Simulation/`):
- `VirtualClock.swift`, `FakeProviders.swift` (location, motion, adres), `FakeIOS.swift`, `ScenarioRunner.swift`, `ScenarioInvariants.swift`.
- Tests: `ScenarioTests.swift`, `ScenarioFuzzTests.swift`, `VirtualClockTests.swift`, `ProviderSmokeTests.swift`.

Docs: `docs/ios-assumptions.md`. Hulpscript: `scripts/add_to_xcodeproj.py`.

---

### Task 1: Protocollen, adapters en service-refactor

**Files:**
- Create: `scripts/add_to_xcodeproj.py`
- Create: `Kilometerregistratie/Services/Platform/TimeSource.swift`
- Create: `Kilometerregistratie/Services/Platform/LocationProviding.swift`
- Create: `Kilometerregistratie/Services/Platform/CoreLocationProvider.swift`
- Create: `Kilometerregistratie/Services/Platform/MotionProviding.swift`
- Create: `Kilometerregistratie/Services/Platform/AddressResolving.swift`
- Create: `KilometerregistratieTests/Simulation/FakeLocationProvider.swift`
- Modify: `Kilometerregistratie/Services/LocationTrackingService.swift`
- Modify: `Kilometerregistratie/App/KilometerregistratieApp.swift`
- Test: `KilometerregistratieTests/LocationTrackingServiceTests.swift`

**Interfaces:**
- Produces (gebruikt door alle latere taken):
  ```swift
  @MainActor final class TimerHandle { init(onCancel: @escaping () -> Void); func cancel(); private(set) var isCancelled: Bool }
  @MainActor protocol TimeSource: AnyObject { var now: Date { get }; func every(_ interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) -> TimerHandle }
  @MainActor protocol LocationProvidingDelegate: AnyObject {
      func locationProvider(didUpdate locations: [CLLocation])
      func locationProviderDidChangeAuthorization()
      func locationProviderDidFail(_ error: Error)
  }
  @MainActor protocol LocationProviding: AnyObject {
      var delegate: LocationProvidingDelegate? { get set }
      var authorizationStatus: CLAuthorizationStatus { get }
      var locationServicesEnabled: Bool { get }
      func requestWhenInUseAuthorization(); func requestAlwaysAuthorization()
      func startUpdatingLocation(); func stopUpdatingLocation()
      func startMonitoringSignificantLocationChanges(); func stopMonitoringSignificantLocationChanges()
      func apply(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance)
      func setBackgroundUpdates(allowed: Bool, showsIndicator: Bool)
  }
  @MainActor protocol MotionProviding: AnyObject {
      var isAvailable: Bool { get }
      func start(handler: @escaping @MainActor (MotionActivityGate.ActivitySample) -> Void)
      func stop()
  }
  @MainActor protocol AddressResolving { func address(latitude: Double, longitude: Double, context: ModelContext) async -> String? }
  LocationTrackingService.init(locationProvider: LocationProviding? = nil, motionProvider: MotionProviding? = nil, time: TimeSource? = nil, geocoder: AddressResolving? = nil)
  LocationTrackingService.appDidBecomeActive() async
  ```
- `FakeLocationProvider` (Taak 1, uitgebreid in Taak 3): `deliver(_:)`, `changeAuthorization(to:)`, `isUpdating`, `isMonitoringSignificantChanges`, `distanceFilter`, `backgroundAllowed`.

- [ ] **Step 1: Hulpscript voor het Xcode-project**

Maak `scripts/add_to_xcodeproj.py`:

```python
#!/usr/bin/env python3
"""Registreert een nieuw Swift-bestand in project.pbxproj.

Gebruik: add_to_xcodeproj.py <pad-relatief-aan-groep> --like <bestaand-broerbestand.swift>
Het nieuwe bestand komt in dezelfde groep en target als het broerbestand.
Voorbeeld: add_to_xcodeproj.py Platform/TimeSource.swift --like TripRecorder.swift
"""
import argparse, re, sys, uuid

PBX = "Kilometerregistratie.xcodeproj/project.pbxproj"

def new_id(text):
    while True:
        candidate = uuid.uuid4().hex[:24].upper()
        if candidate not in text:
            return candidate

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--like", required=True)
    args = parser.parse_args()
    name = args.path.rsplit("/", 1)[-1]

    s = open(PBX).read()
    if f"/* {name} */" in s:
        sys.exit(f"{name} staat al in het project")

    ref = re.search(r"\t\t(\w{24}) /\* %s \*/ = \{isa = PBXFileReference" % re.escape(args.like), s)
    build = re.search(r"\t\t(\w{24}) /\* %s in Sources \*/ = \{isa = PBXBuildFile" % re.escape(args.like), s)
    if not ref or not build:
        sys.exit(f"{args.like} niet gevonden in het project")
    ref_id, build_id = ref.group(1), build.group(1)
    file_id, new_build_id = new_id(s), None
    s_with = s + file_id
    new_build_id = new_id(s_with)

    # PBXBuildFile
    s = s.replace("/* End PBXBuildFile section */",
        f"\t\t{new_build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {name} */; }};\n/* End PBXBuildFile section */", 1)
    # PBXFileReference
    s = s.replace("/* End PBXFileReference section */",
        f"\t\t{file_id} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = {args.path}; sourceTree = \"<group>\"; }};\n/* End PBXFileReference section */", 1)
    # groep
    group_line = re.search(r"(\t+)%s /\* %s \*/,\n" % (ref_id, re.escape(args.like)), s)
    s = s[:group_line.end()] + f"{group_line.group(1)}{file_id} /* {name} */,\n" + s[group_line.end():]
    # sources-fase
    src_line = re.search(r"(\t+)%s /\* %s in Sources \*/,\n" % (build_id, re.escape(args.like)), s)
    s = s[:src_line.end()] + f"{src_line.group(1)}{new_build_id} /* {name} in Sources */,\n" + s[src_line.end():]

    open(PBX, "w").write(s)
    print(f"{name} toegevoegd")

main()
```

- [ ] **Step 2: Schrijf de falende tests** (nieuwe `FakeLocationProvider` en service-tests)

Maak `KilometerregistratieTests/Simulation/FakeLocationProvider.swift`:

```swift
import CoreLocation
@testable import Kilometerregistratie

/// Nagebootste locatiebron: legt elke aanroep vast en levert alleen locaties
/// af als een test dat zegt. De regels waaronder iOS dat zou doen zitten in
/// `FakeIOS`.
@MainActor
final class FakeLocationProvider: LocationProviding {
    weak var delegate: LocationProvidingDelegate?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var locationServicesEnabled = true

    private(set) var isUpdating = false
    private(set) var isMonitoringSignificantChanges = false
    private(set) var distanceFilter: CLLocationDistance = 25
    private(set) var backgroundAllowed = false
    private(set) var calls: [String] = []

    func requestWhenInUseAuthorization() { calls.append("requestWhenInUse") }
    func requestAlwaysAuthorization() { calls.append("requestAlways") }
    func startUpdatingLocation() { isUpdating = true; calls.append("startUpdating") }
    func stopUpdatingLocation() { isUpdating = false; calls.append("stopUpdating") }
    func startMonitoringSignificantLocationChanges() { isMonitoringSignificantChanges = true; calls.append("startSignificant") }
    func stopMonitoringSignificantLocationChanges() { isMonitoringSignificantChanges = false; calls.append("stopSignificant") }
    func apply(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) {
        self.distanceFilter = distanceFilter
        calls.append("apply(\(distanceFilter))")
    }
    func setBackgroundUpdates(allowed: Bool, showsIndicator: Bool) { backgroundAllowed = allowed }

    /// Levert locaties af zoals CoreLocation dat doet.
    func deliver(_ locations: [CLLocation]) {
        delegate?.locationProvider(didUpdate: locations)
    }

    /// Wijzigt de toestemming en meldt dat zoals iOS dat doet.
    func changeAuthorization(to status: CLAuthorizationStatus) {
        authorizationStatus = status
        delegate?.locationProviderDidChangeAuthorization()
    }

    /// Een nieuw proces start zonder lopende updates; alleen het
    /// significante-wijzigingen-abonnement blijft bij het systeem staan.
    func resetForNewProcess() {
        isUpdating = false
        backgroundAllowed = false
        delegate = nil
    }
}
```

Voeg toe onder in `KilometerregistratieTests/LocationTrackingServiceTests.swift` (vóór de laatste `}`):

```swift

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
```

- [ ] **Step 3: Registreer het fake-bestand en draai de tests (moeten falen)**

```bash
python3 scripts/add_to_xcodeproj.py Simulation/FakeLocationProvider.swift --like TripRecorderTests.swift
```
Run: `TEST -only-testing:KilometerregistratieTests/LocationTrackingServiceTests`
Expected: FAIL (compileerfout: `LocationProviding` / `init(locationProvider:)` bestaan niet).

- [ ] **Step 4: Maak de protocollen en adapters**

`Kilometerregistratie/Services/Platform/TimeSource.swift`:

```swift
import Foundation

/// Annuleerbare herhalende taak van een `TimeSource`.
@MainActor
final class TimerHandle {
    private let onCancel: () -> Void
    private(set) var isCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

/// Bron van tijd en herhalende timers. De service gebruikt dit in plaats van
/// `Date.now` en `Task.sleep`, zodat tests de tijd zelf kunnen laten lopen.
@MainActor
protocol TimeSource: AnyObject {
    var now: Date { get }
    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) -> TimerHandle
}

@MainActor
final class SystemTimeSource: TimeSource {
    var now: Date { .now }

    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) -> TimerHandle {
        let task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await action()
            }
        }
        return TimerHandle { task.cancel() }
    }
}
```

`Kilometerregistratie/Services/Platform/LocationProviding.swift`:

```swift
import CoreLocation

@MainActor
protocol LocationProvidingDelegate: AnyObject {
    func locationProvider(didUpdate locations: [CLLocation])
    func locationProviderDidChangeAuthorization()
    func locationProviderDidFail(_ error: Error)
}

/// Dunne laag om `CLLocationManager`, zodat de service zonder CoreLocation
/// getest kan worden. Bevat bewust geen logica.
@MainActor
protocol LocationProviding: AnyObject {
    var delegate: LocationProvidingDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var locationServicesEnabled: Bool { get }

    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
    func apply(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance)
    func setBackgroundUpdates(allowed: Bool, showsIndicator: Bool)
}
```

`Kilometerregistratie/Services/Platform/CoreLocationProvider.swift`:

```swift
import CoreLocation

/// Echte adapter: alleen doorgeven aan `CLLocationManager`, geen beslissingen.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    weak var delegate: LocationProvidingDelegate?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = true
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var locationServicesEnabled: Bool { CLLocationManager.locationServicesEnabled() }

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestAlwaysAuthorization() { manager.requestAlwaysAuthorization() }
    func startUpdatingLocation() { manager.startUpdatingLocation() }
    func stopUpdatingLocation() { manager.stopUpdatingLocation() }
    func startMonitoringSignificantLocationChanges() { manager.startMonitoringSignificantLocationChanges() }
    func stopMonitoringSignificantLocationChanges() { manager.stopMonitoringSignificantLocationChanges() }

    func apply(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) {
        manager.desiredAccuracy = accuracy
        manager.distanceFilter = distanceFilter
    }

    func setBackgroundUpdates(allowed: Bool, showsIndicator: Bool) {
        manager.allowsBackgroundLocationUpdates = allowed
        manager.showsBackgroundLocationIndicator = showsIndicator
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            delegate?.locationProviderDidChangeAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            delegate?.locationProvider(didUpdate: locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            delegate?.locationProviderDidFail(error)
        }
    }
}
```

`Kilometerregistratie/Services/Platform/MotionProviding.swift`:

```swift
import CoreMotion

@MainActor
protocol MotionProviding: AnyObject {
    var isAvailable: Bool { get }
    func start(handler: @escaping @MainActor (MotionActivityGate.ActivitySample) -> Void)
    func stop()
}

@MainActor
final class CoreMotionProvider: MotionProviding {
    private let manager = CMMotionActivityManager()

    var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    func start(handler: @escaping @MainActor (MotionActivityGate.ActivitySample) -> Void) {
        manager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            MainActor.assumeIsolated {
                handler(MotionActivityGate.ActivitySample(
                    automotive: activity.automotive,
                    confidence: MotionActivityGate.ActivitySample.Confidence(activity.confidence)
                ))
            }
        }
    }

    func stop() {
        manager.stopActivityUpdates()
    }
}

private extension MotionActivityGate.ActivitySample.Confidence {
    init(_ confidence: CMMotionActivityConfidence) {
        switch confidence {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        @unknown default: self = .low
        }
    }
}
```

`Kilometerregistratie/Services/Platform/AddressResolving.swift`:

```swift
import Foundation
import SwiftData

/// Zoekt een adres bij een coördinaat. Met een protocol kunnen tests zonder
/// netwerk draaien.
@MainActor
protocol AddressResolving {
    func address(latitude: Double, longitude: Double, context: ModelContext) async -> String?
}

extension GeocodingService: AddressResolving {}
```

Registreer ze:
```bash
python3 scripts/add_to_xcodeproj.py Platform/TimeSource.swift --like TripRecorder.swift
python3 scripts/add_to_xcodeproj.py Platform/LocationProviding.swift --like TripRecorder.swift
python3 scripts/add_to_xcodeproj.py Platform/CoreLocationProvider.swift --like TripRecorder.swift
python3 scripts/add_to_xcodeproj.py Platform/MotionProviding.swift --like TripRecorder.swift
python3 scripts/add_to_xcodeproj.py Platform/AddressResolving.swift --like TripRecorder.swift
```

- [ ] **Step 5: Pas `LocationTrackingService` aan**

Voer deze vervangingen uit in `Kilometerregistratie/Services/LocationTrackingService.swift` (de volgorde maakt niet uit):

1. Imports: verwijder `import CoreMotion`.
2. `final class LocationTrackingService: NSObject {` wordt `final class LocationTrackingService {`.
3. Vervang de drie properties
   ```swift
   private let manager = CLLocationManager()
   private let motionActivityManager = CMMotionActivityManager()
   ```
   en `private let geocoder = GeocodingService()` door:
   ```swift
   private let locationProvider: LocationProviding
   private let motionProvider: MotionProviding
   private let time: TimeSource
   private let geocoder: AddressResolving
   ```
4. Vervang `override init() { … }` door:
   ```swift
   init(
       locationProvider: LocationProviding? = nil,
       motionProvider: MotionProviding? = nil,
       time: TimeSource? = nil,
       geocoder: AddressResolving? = nil
   ) {
       let locationProvider = locationProvider ?? CoreLocationProvider()
       self.locationProvider = locationProvider
       self.motionProvider = motionProvider ?? CoreMotionProvider()
       self.time = time ?? SystemTimeSource()
       self.geocoder = geocoder ?? GeocodingService()
       locationProvider.delegate = self
       authorizationStatus = locationProvider.authorizationStatus
   }
   ```
5. `manager.requestAlwaysAuthorization()` → `locationProvider.requestAlwaysAuthorization()`; `manager.requestWhenInUseAuthorization()` → `locationProvider.requestWhenInUseAuthorization()`; `manager.startMonitoringSignificantLocationChanges()` / `stopMonitoring…` → `locationProvider.…`; `manager.startUpdatingLocation()` / `stopUpdatingLocation()` → `locationProvider.…`.
6. `applyAccuracyPreference`: vervang in elke case de twee regels `manager.desiredAccuracy = X` / `manager.distanceFilter = Y` door `locationProvider.apply(accuracy: X, distanceFilter: Y)`:
   - `.batterySaver`: `kCLLocationAccuracyHundredMeters`, `50`
   - `.balanced`: `kCLLocationAccuracyNearestTenMeters`, `25`
   - `.precise`: `kCLLocationAccuracyBest`, `10`
7. `beginContinuousUpdates`: vervang de twee regels `manager.allowsBackgroundLocationUpdates = true` + `manager.showsBackgroundLocationIndicator = true` door `locationProvider.setBackgroundUpdates(allowed: true, showsIndicator: true)`. In `stopContinuousUpdates`: `manager.allowsBackgroundLocationUpdates = false` → `locationProvider.setBackgroundUpdates(allowed: false, showsIndicator: false)`.
8. Beweging: vervang `startMotionUpdatesIfAvailable` en `stopMotionUpdates` door:
   ```swift
   private func startMotionUpdatesIfAvailable() {
       guard motionProvider.isAvailable else { return }
       motionProvider.start { [weak self] sample in
           self?.latestActivity = sample
       }
   }

   private func stopMotionUpdates() {
       motionProvider.stop()
       latestActivity = nil
   }
   ```
9. Tijd: `Task { await stopRecording(endDate: .now) }` (twee plekken: in `applySettings` en `handleAuthorizationChange`) → `Task { await stopRecording(endDate: time.now) }`; in `startRecording`: `lastSampleAt = .now` → `lastSampleAt = time.now`.
   `func resumeIfNeeded(context: ModelContext, now: Date = .now) async {` → `func resumeIfNeeded(context: ModelContext, now: Date? = nil) async {` met als eerste regel `let now = now ?? time.now`.
   `func checkWatchdog(now: Date = .now) async {` → `func checkWatchdog(now: Date? = nil) async {` met als eerste regel `let now = now ?? time.now`.
10. Watchdog-timer: vervang `private var watchdogTask: Task<Void, Never>?` door `private var watchdogTimer: TimerHandle?`; in `stopContinuousUpdates` vervang `watchdogTask?.cancel(); watchdogTask = nil` door `watchdogTimer?.cancel(); watchdogTimer = nil`; vervang `startWatchdog()` door:
    ```swift
    private func startWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = time.every(30) { [weak self] in
            await self?.checkWatchdog()
        }
    }
    ```
11. `authorizationStatus = manager.authorizationStatus` in `handleAuthorizationChange` → `authorizationStatus = locationProvider.authorizationStatus`.
12. Voeg toe (naast `checkWatchdog`):
    ```swift
    /// De app is weer actief (voorgrond). Een opgeschorte app voert geen
    /// timers uit; sluit een verlopen opname direct af.
    func appDidBecomeActive() async {
        await checkWatchdog()
    }
    ```
13. Vervang de hele `extension LocationTrackingService: CLLocationManagerDelegate { … }` én de private `Confidence`-extensie onderaan door:
    ```swift
    extension LocationTrackingService: LocationProvidingDelegate {
        func locationProvider(didUpdate locations: [CLLocation]) {
            handle(locations: locations)
        }

        func locationProviderDidChangeAuthorization() {
            handleAuthorizationChange()
        }

        func locationProviderDidFail(_ error: Error) {
            // Tijdelijke GPS-uitval is normaal (tunnel, parkeergarage); de
            // detector en route-opname herstellen zodra er weer samples komen.
            // Alleen het systeemwide uitschakelen van locatievoorzieningen tonen
            // we aan de gebruiker, want dat registreert helemaal niets meer
            // totdat de gebruiker het zelf weer aanzet.
            guard (error as? CLError)?.code == .denied, !locationProvider.locationServicesEnabled else { return }
            currentIssue = .locationServicesDisabled
        }
    }
    ```
14. `handleAuthorizationChange` mag `internal` worden i.p.v. `fileprivate` als de compiler daar over klaagt.

In `Kilometerregistratie/App/KilometerregistratieApp.swift`: vervang
`Task { await locationService.checkWatchdog() }` door `Task { await locationService.appDidBecomeActive() }`.

- [ ] **Step 6: Draai de volledige suite**

Run: `TEST`
Expected: PASS, 82 tests (79 bestaande + 3 nieuwe), 0 failures. Bij een Swift-isolatiefout in `CoreMotionProvider` (de `MainActor.assumeIsolated`): vervang door `Task { @MainActor in handler(...) }`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Injecteer locatie, beweging, adres en tijd in LocationTrackingService

Vier protocollen met echte adapters als standaard, zodat scenario's de
service zonder CoreLocation kunnen aansturen. Gedrag voor de gebruiker
blijft gelijk.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: VirtualClock en overige fakes

**Files:**
- Create: `KilometerregistratieTests/Simulation/VirtualClock.swift`
- Create: `KilometerregistratieTests/Simulation/FakeProviders.swift`
- Create: `KilometerregistratieTests/VirtualClockTests.swift`
- Test: `KilometerregistratieTests/LocationTrackingServiceTests.swift`

**Interfaces:**
- Consumes: `TimeSource`, `TimerHandle`, `MotionProviding`, `AddressResolving` (Taak 1).
- Produces:
  ```swift
  @MainActor final class VirtualClock: TimeSource {
      init(start: Date)
      private(set) var now: Date
      var timersEnabled: Bool { get set }   // FakeIOS zet dit uit tijdens opschorten
      var nextTimerDate: Date? { get }       // nil als timers uit staan of ontbreken
      func advance(to date: Date) async      // vuurt verlopen timers in volgorde, zet daarna now = date
      func resumeTimers() async              // aan; elke verlopen timer vuurt één keer
      func removeAllTimers()
  }
  @MainActor final class FakeMotionProvider: MotionProviding { var isRunning: Bool; func send(automotive: Bool, confidence: MotionActivityGate.ActivitySample.Confidence); func resetForNewProcess() }
  @MainActor struct FakeAddressResolver: AddressResolving   // geeft "Teststraat 1" terug
  ```

- [ ] **Step 1: Schrijf de falende tests**

`KilometerregistratieTests/VirtualClockTests.swift`:

```swift
import XCTest
@testable import Kilometerregistratie

@MainActor
final class VirtualClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testTimersFireInOrderWhileAdvancing() async {
        let clock = VirtualClock(start: start)
        var fired: [String] = []
        _ = clock.every(30) { fired.append("a@\(Int(clock.now.timeIntervalSince(self.start)))") }
        _ = clock.every(45) { fired.append("b@\(Int(clock.now.timeIntervalSince(self.start)))") }

        await clock.advance(to: start.addingTimeInterval(100))

        XCTAssertEqual(fired, ["a@30", "b@45", "a@60", "a@90", "b@90"])
        XCTAssertEqual(clock.now, start.addingTimeInterval(100))
    }

    func testDisabledTimersDoNotFireAndFireOnceOnResume() async {
        let clock = VirtualClock(start: start)
        var count = 0
        _ = clock.every(30) { count += 1 }

        clock.timersEnabled = false
        await clock.advance(to: start.addingTimeInterval(600))
        XCTAssertEqual(count, 0, "opgeschorte app voert geen timers uit (A3)")

        await clock.resumeTimers()
        XCTAssertEqual(count, 1, "na hervatten vuurt een verlopen timer één keer")
    }

    func testCancelledTimerStopsFiring() async {
        let clock = VirtualClock(start: start)
        var count = 0
        let handle = clock.every(30) { count += 1 }
        await clock.advance(to: start.addingTimeInterval(30))
        handle.cancel()
        await clock.advance(to: start.addingTimeInterval(300))
        XCTAssertEqual(count, 1)
    }
}
```

Voeg toe aan `LocationTrackingServiceTests.swift` (vóór de laatste `}`):

```swift

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
```

- [ ] **Step 2: Registreer en draai (moet falen)**

```bash
python3 scripts/add_to_xcodeproj.py Simulation/VirtualClock.swift --like TripRecorderTests.swift
python3 scripts/add_to_xcodeproj.py Simulation/FakeProviders.swift --like TripRecorderTests.swift
python3 scripts/add_to_xcodeproj.py VirtualClockTests.swift --like TripRecorderTests.swift
```
Maak eerst lege bestanden aan zodat het project bouwt: `touch` de twee Simulation-bestanden vóór het script.
Run: `TEST -only-testing:KilometerregistratieTests/VirtualClockTests`
Expected: FAIL (compileerfout: `VirtualClock` bestaat niet).

- [ ] **Step 3: Implementeer `VirtualClock`**

`KilometerregistratieTests/Simulation/VirtualClock.swift`:

```swift
import Foundation
@testable import Kilometerregistratie

/// Virtuele tijd voor scenario's. De tijd loopt alleen als een test dat zegt;
/// timers gaan af op hun eigen momenten tijdens `advance(to:)`.
@MainActor
final class VirtualClock: TimeSource {
    private(set) var now: Date
    /// FakeIOS zet dit uit zolang de app is opgeschort (A3).
    var timersEnabled = true

    private struct ScheduledTimer {
        let id: Int
        let interval: TimeInterval
        var nextFire: Date
        let action: @MainActor () async -> Void
    }
    private var timers: [ScheduledTimer] = []
    private var nextID = 0

    init(start: Date) {
        now = start
    }

    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) -> TimerHandle {
        let id = nextID
        nextID += 1
        timers.append(ScheduledTimer(id: id, interval: interval, nextFire: now.addingTimeInterval(interval), action: action))
        return TimerHandle { [weak self] in
            self?.timers.removeAll { $0.id == id }
        }
    }

    var nextTimerDate: Date? {
        guard timersEnabled else { return nil }
        return timers.map(\.nextFire).min()
    }

    func advance(to date: Date) async {
        while timersEnabled,
              let index = timers.indices.min(by: { timers[$0].nextFire < timers[$1].nextFire }),
              timers[index].nextFire <= date {
            let timer = timers[index]
            now = max(now, timer.nextFire)
            timers[index].nextFire = timer.nextFire.addingTimeInterval(timer.interval)
            await timer.action()
        }
        now = max(now, date)
    }

    func resumeTimers() async {
        timersEnabled = true
        // Een echte `Task.sleep` die door opschorten heen liep, vuurt na het
        // hervatten één keer en loopt daarna weer op zijn normale ritme.
        let overdue = timers.filter { $0.nextFire <= now }
        for timer in overdue {
            if let index = timers.firstIndex(where: { $0.id == timer.id }) {
                timers[index].nextFire = now.addingTimeInterval(timer.interval)
            }
            await timer.action()
        }
    }

    func removeAllTimers() {
        timers.removeAll()
    }
}
```

`KilometerregistratieTests/Simulation/FakeProviders.swift`:

```swift
import Foundation
import SwiftData
@testable import Kilometerregistratie

@MainActor
final class FakeMotionProvider: MotionProviding {
    var isAvailable = true
    private(set) var isRunning = false
    private var handler: (@MainActor (MotionActivityGate.ActivitySample) -> Void)?

    func start(handler: @escaping @MainActor (MotionActivityGate.ActivitySample) -> Void) {
        isRunning = true
        self.handler = handler
    }

    func stop() {
        isRunning = false
        handler = nil
    }

    func send(automotive: Bool, confidence: MotionActivityGate.ActivitySample.Confidence = .high) {
        handler?(MotionActivityGate.ActivitySample(automotive: automotive, confidence: confidence))
    }

    func resetForNewProcess() {
        isRunning = false
        handler = nil
    }
}

/// Geeft altijd hetzelfde adres terug; raakt het netwerk niet.
@MainActor
struct FakeAddressResolver: AddressResolving {
    func address(latitude: Double, longitude: Double, context: ModelContext) async -> String? {
        "Teststraat 1"
    }
}
```

- [ ] **Step 4: Draai de tests**

Run: `TEST`
Expected: PASS, 86 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "VirtualClock en nagebootste beweging- en adresbron voor scenario's

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: FakeIOS, ScenarioRunner en de eerste scenario's

**Files:**
- Modify: `Kilometerregistratie/Services/TripRecorder.swift`
- Modify: `KilometerregistratieTests/TripRecorderTests.swift`
- Create: `KilometerregistratieTests/Simulation/FakeIOS.swift`
- Create: `KilometerregistratieTests/Simulation/ScenarioRunner.swift`
- Create: `KilometerregistratieTests/Simulation/ScenarioInvariants.swift`
- Create: `KilometerregistratieTests/ScenarioTests.swift`

**Interfaces:**
- Consumes: alles uit Taak 1 en 2.
- Produces:
  ```swift
  struct TripRecorder { var now: () -> Date }   // standaard { .now }; scenario's geven de virtuele klok mee

  struct IOSParameters {
      var autoPauseAfter: TimeInterval = 600          // A2
      var significantChangeDistance: Double = 500     // A5
      var wakesWhenUpdatesResume = true               // A4
      var revokingPermissionTerminatesApp = true      // A9
  }
  enum AppState { case foreground, background, suspended, terminated }

  @MainActor final class FakeIOS {
      struct Fix { var latitude: Double; var longitude: Double; var speed: Double; var accuracy: Double; var timestamp: Date }
      var params: IOSParameters
      private(set) var appState: AppState
      var onRelaunch: (() async -> Void)?
      func offer(_ fix: Fix) async        // beslist volgens A1/A2/A4/A5 of de service het sample ziet
      func goToBackground()               // voorgrond -> achtergrond
      func suspend()                      // achtergrond -> opgeschort (A3): timers uit
      func resume() async                 // -> voorgrond, timers aan
      func terminate()                    // proces weg (A6)
  }

  enum ScenarioMode { case manual, hybrid, automatic }

  @MainActor final class ScenarioRunner {
      init(mode: ScenarioMode, stopAfterMinutes: Int = 3, ios: IOSParameters = IOSParameters()) throws
      let clock: VirtualClock; let ios: FakeIOS; let context: ModelContext
      private(set) var service: LocationTrackingService
      var trips: [Trip] { get }            // oplopend op startDate
      var openTrips: [Trip] { get }
      // wereld
      func drive(meters: Double, speed: Double = 14, accuracy: Double = 5, speedKnown: Bool = true) async
      func stand(for seconds: TimeInterval) async
      func jump(meters: Double, over seconds: TimeInterval) async   // verplaatsen zonder fixes (tunnel/gat)
      func wait(for seconds: TimeInterval) async                    // tijd laten lopen zonder fixes
      // app
      func appToBackground(); func appSuspend(); func appResume() async; func appKill(); func appRelaunch() async
      func revokePermission() async
      // gebruiker
      func userTapsStart() throws; func userTapsStop() async throws
      func settle() async
      // controle
      func assertInvariants(file: StaticString, line: UInt) throws
  }
  ```

- [ ] **Step 1: Maak `TripRecorder` tijd-injecteerbaar (test eerst)**

Voeg toe aan `KilometerregistratieTests/TripRecorderTests.swift` (vóór de laatste `}`):

```swift

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
```
Run: `TEST -only-testing:KilometerregistratieTests/TripRecorderTests` → Expected: FAIL (compileerfout, `TripRecorder(now:)` bestaat niet).

Wijzig `Kilometerregistratie/Services/TripRecorder.swift`: voeg in de struct toe
```swift
    /// Tijd van START/STOP; scenario-tests geven een virtuele klok mee.
    var now: () -> Date = { .now }
```
en vervang `Trip(startDate: .now, vehicle: vehicle)` door `Trip(startDate: now(), vehicle: vehicle)` en `{ $0.endDate = .now }` door `{ $0.endDate = end }` met `let end = now()` vóór de `update`-aanroep. Run dezelfde tests → Expected: PASS.

- [ ] **Step 2: Schrijf het eerste scenario (falend, want de runner bestaat niet)**

`KilometerregistratieTests/ScenarioTests.swift`:

```swift
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
        try s.assertInvariants()
    }
}
```
Registreer: `python3 scripts/add_to_xcodeproj.py ScenarioTests.swift --like TripRecorderTests.swift` (en maak lege `FakeIOS.swift`, `ScenarioRunner.swift`, `ScenarioInvariants.swift` aan en registreer ze met `--like TripRecorderTests.swift`, pad `Simulation/<naam>.swift`).
Run: `TEST -only-testing:KilometerregistratieTests/ScenarioTests` → Expected: FAIL (compileerfout).

- [ ] **Step 3: Implementeer `FakeIOS`**

`KilometerregistratieTests/Simulation/FakeIOS.swift`:

```swift
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
            await deliver(fix)

        case .suspended:
            // A4/A5: alleen beweging maakt een opgeschorte app wakker.
            let wakesByUpdates = location.isUpdating && params.wakesWhenUpdatesResume && isMoving
            let wakesBySignificant = location.isMonitoringSignificantChanges && significantDue(position)
            guard wakesByUpdates || wakesBySignificant else { return }
            if wakesBySignificant { significantAnchor = position }
            appState = .background
            clock.timersEnabled = true
            await clock.resumeTimers()
            await deliver(fix)

        case .foreground, .background:
            if location.isUpdating {
                if isMoving {
                    await deliver(fix)
                } else if appState == .background,
                          let last = lastMovementAt,
                          fix.timestamp.timeIntervalSince(last) >= params.autoPauseAfter {
                    // A2 + A3: iOS pauzeert de updates; de app wordt opgeschort.
                    suspend()
                }
            } else if location.isMonitoringSignificantChanges, significantDue(position) {
                significantAnchor = position
                await deliver(fix)
            }
        }
    }

    private func deliver(_ fix: Fix) async {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
            altitude: 0,
            horizontalAccuracy: fix.accuracy,
            verticalAccuracy: fix.accuracy,
            course: 0,
            speed: fix.speed,
            timestamp: fix.timestamp
        )
        self.location.deliver([location])
    }

    private func significantDue(_ position: (lat: Double, lon: Double)) -> Bool {
        guard let anchor = significantAnchor else { return true }
        return distance(anchor, position) >= params.significantChangeDistance
    }

    private func distance(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        GeoDistance.meters(fromLatitude: a.lat, longitude: a.lon, toLatitude: b.lat, longitude: b.lon)
    }
}
```

- [ ] **Step 4: Implementeer `ScenarioRunner`**

`KilometerregistratieTests/Simulation/ScenarioRunner.swift`:

```swift
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
    private(set) var truthDrivenMeters = 0.0

    init(mode: ScenarioMode, stopAfterMinutes: Int = 3, ios params: IOSParameters = IOSParameters()) throws {
        self.mode = mode
        self.stopAfterMinutes = stopAfterMinutes
        container = try ModelContainer(
            for: AppSchema.schema,
            configurations: [ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)
        clock = VirtualClock(start: Date(timeIntervalSince1970: 1_700_000_000))
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
        guard ios.appState == .terminated else { return }
        await launchService()
        await ios.resume()
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
    func userTapsStart() throws {
        let recorder = TripRecorder(now: { [clock] in clock.now })
        if let trip = try recorder.start(context: context, vehicle: nil) {
            service.beginRouteRecording(for: trip)
        }
    }

    /// Gedraagt zich als `HomeView.toggleRecording` bij STOP.
    func userTapsStop() async throws {
        await service.stopRecording(endDate: clock.now)
        try TripRecorder(now: { [clock] in clock.now }).stop(context: context)
        await settle()
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
```

- [ ] **Step 5: Implementeer de invarianten**

`KilometerregistratieTests/Simulation/ScenarioInvariants.swift`:

```swift
import XCTest
@testable import Kilometerregistratie

extension ScenarioRunner {
    /// Eisen die voor élk scenario gelden (zie spec, hoofdstuk 6).
    func assertInvariants(file: StaticString = #filePath, line: UInt = #line) throws {
        let all = trips

        // 1. Nooit meer dan één open rit.
        XCTAssertLessThanOrEqual(all.filter { $0.endDate == nil }.count, 1, "meer dan één open rit", file: file, line: line)

        // 2. endDate >= startDate en geen overlap tussen afgesloten ritten.
        let closed = all.filter { $0.endDate != nil }
        for trip in closed {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(trip.endDate), trip.startDate, "einde vóór start", file: file, line: line)
        }
        for (a, b) in zip(closed, closed.dropFirst()) {
            XCTAssertLessThanOrEqual(try XCTUnwrap(a.endDate), b.startDate, "overlappende ritten", file: file, line: line)
        }

        // 4. Einde van een automatische rit ligt niet later dan het laatste
        //    beweegmoment + drempel + 60 s (watchdog-marge) + 30 s (timer) + 1 s.
        let slack = TimeInterval(stopAfterMinutes * 60) + 60 + 30 + 1
        for trip in closed where trip.isAutomaticallyRecorded {
            let end = try XCTUnwrap(trip.endDate)
            let lastMovement = truthMovementTimes.last { $0 <= end } ?? trip.startDate
            XCTAssertLessThanOrEqual(
                end.timeIntervalSince(lastMovement), slack,
                "rit eindigt \(Int(end.timeIntervalSince(lastMovement))) s na het laatste beweegmoment",
                file: file, line: line
            )
        }

        // 5/6. Nooit meer afstand dan er is gereden (gaten tellen niet mee).
        let registeredMeters = all.reduce(0) { $0 + $1.distanceKm * 1000 }
        XCTAssertLessThanOrEqual(
            registeredMeters, truthDrivenMeters * 1.03 + 100,
            "meer afstand geregistreerd dan gereden", file: file, line: line
        )
    }

    /// Invariant 3: na afloop staat er geen open automatische rit meer. Alleen
    /// aanroepen als de app draait en er lang genoeg is gewacht.
    func assertNoOpenAutomaticTrip(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            openTrips.filter(\.isAutomaticallyRecorded).isEmpty,
            "open automatische rit na afloop", file: file, line: line
        )
    }
}
```

Breid het eerste scenario uit met `s.assertNoOpenAutomaticTrip()` vóór `try s.assertInvariants()`.

- [ ] **Step 6: Voeg de twee scenario's voor opschorten en kill toe**

Voeg toe aan `ScenarioTests.swift` (vóór de laatste `}`):

```swift

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
```

- [ ] **Step 7: Draai en los verschillen op**

Run: `TEST -only-testing:KilometerregistratieTests/ScenarioTests`
Expected: PASS (3 tests). Faalt een scenario, onderzoek dan eerst of de fout in de runner/FakeIOS zit (model klopt niet met de bedoeling) of een echte bug in de app. Een echte bug: stop en rapporteer aan de gebruiker, repareer niet stilletjes binnen deze taak.

Run: `TEST` → Expected: alle tests groen.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "FakeIOS en ScenarioRunner met invarianten en eerste scenario's

TripRecorder krijgt een injecteerbare klok. Scenario's spelen op virtuele
tijd: rit zonder opschorten, opschorten en heropenen, kill en herstel.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Scenario's voor de situaties uit het onderzoek

**Files:**
- Modify: `KilometerregistratieTests/ScenarioTests.swift`

**Interfaces:**
- Consumes: `ScenarioRunner`, `IOSParameters`, `FakeIOS` (Taak 3).
- Produces: één test per geval uit het onderzoek (nummers verwijzen naar het overzicht van de bugreeks): 1, 2, 3, 6 (twee varianten), 7, 8, 9, 10, 11, 12, 13.

Elke test hieronder is volledig; voeg ze alle toe aan `ScenarioTests.swift` (vóór de laatste `}`), draai daarna `TEST -only-testing:KilometerregistratieTests/ScenarioTests`. Verwacht PASS; bij een failure geldt de regel uit Taak 3 Step 7.

- [ ] **Step 1: Geval 1 en 2: handmatig**

```swift

    // Geval 1: handmatig START, niet op STOP. De rit blijft bewust open; de
    // opname blijft doorlopen (geen watchdog-stop op stilte). Leunt op: A1.
    func testManualTripStaysOpenAndRecordingContinuesDuringLongStop() async throws {
        let s = try ScenarioRunner(mode: .manual)
        try s.userTapsStart()
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
```

- [ ] **Step 2: Geval 3, 6 en 7: automatisch/hybride**

```swift

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

    // Geval 7: hybride, handmatige rit; er komt geen tweede (automatische) rit
    // naast en na STOP staat er niets open. Leunt op: A1.
    func testHybridManualTripIsNotDuplicatedByDetection() async throws {
        let s = try ScenarioRunner(mode: .hybrid)
        try s.userTapsStart()
        await s.drive(meters: 8_000)
        try await s.userTapsStop()
        await s.stand(for: 10 * 60)

        XCTAssertEqual(s.trips.count, 1)
        XCTAssertEqual(s.openTrips.count, 0)
        try s.assertInvariants()
    }
```

- [ ] **Step 3: Geval 8, 9 en 12**

```swift

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
```

- [ ] **Step 4: Geval 10, 11 en 13**

```swift

    // Geval 10: bij "Alleen bij gebruik" kan een beëindigde app niet door een
    // significante wijziging worden gestart; er ontstaat dus geen rit. Het model
    // kent dat niet (alleen "Altijd"); dit scenario zet de service op handmatige
    // modus zodat gedrag zonder detectie is vastgelegd. Leunt op: A5.
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
```

- [ ] **Step 5: Draai alles**

Run: `TEST`
Expected: PASS. Noteer in je rapport welke scenario's een echte app-bug aan het licht brachten (stop dan, zie Taak 3 Step 7).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Scenario's voor de gevallen uit het onderzoek naar niet-afsluitende ritten

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Seed-gestuurde fuzz-test

**Files:**
- Create: `KilometerregistratieTests/ScenarioFuzzTests.swift`

**Interfaces:**
- Consumes: `ScenarioRunner`, `IOSParameters` (Taak 3).
- Produces: `ScenarioFuzzTests.runScenario(seed:)` en regressietests voor mislukte seeds.

- [ ] **Step 1: Schrijf de fuzz-test**

`KilometerregistratieTests/ScenarioFuzzTests.swift`:

```swift
import XCTest
@testable import Kilometerregistratie

/// Deterministische pseudo-random generator, zodat een seed altijd dezelfde
/// reeks stappen oplevert.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class ScenarioFuzzTests: XCTestCase {
    private enum Step: CaseIterable {
        case drive, stand, tunnel, gap, background, suspend, resume, kill, relaunch, revoke, start, stop
    }

    /// Speelt een willekeurige reeks stappen af en controleert de invarianten.
    private func runScenario(seed: UInt64, file: StaticString = #filePath, line: UInt = #line) async throws {
        var rng = SeededGenerator(seed: seed)
        let mode: ScenarioMode = [.manual, .hybrid, .automatic].randomElement(using: &rng)!
        var ios = IOSParameters()
        ios.autoPauseAfter = Double(Int.random(in: 300...1200, using: &rng))   // A2: 5 tot 20 minuten
        ios.wakesWhenUpdatesResume = Bool.random(using: &rng)                  // A4 in beide richtingen
        let s = try ScenarioRunner(mode: mode, stopAfterMinutes: Int.random(in: 1...6, using: &rng), ios: ios)

        for _ in 0..<Int.random(in: 4...14, using: &rng) {
            switch Step.allCases.randomElement(using: &rng)! {
            case .drive: await s.drive(meters: Double(Int.random(in: 500...15_000, using: &rng)),
                                       speedKnown: Int.random(in: 0...4, using: &rng) != 0)
            case .stand: await s.stand(for: Double(Int.random(in: 30...2400, using: &rng)))
            case .tunnel: await s.jump(meters: Double(Int.random(in: 200...5_000, using: &rng)),
                                       over: Double(Int.random(in: 20...900, using: &rng)))
            case .gap: await s.wait(for: Double(Int.random(in: 60...1800, using: &rng)))
            case .background: s.appToBackground()
            case .suspend: s.appSuspend()
            case .resume: await s.appResume()
            case .kill: s.appKill()
            case .relaunch: await s.appRelaunch()
            case .revoke: await s.revokePermission()
            case .start: try? s.userTapsStart()
            case .stop: try? await s.userTapsStop()
            }
            try s.assertInvariants(file: file, line: line)
        }

        // Afronden: app draait, tijd verstrijkt, de gebruiker sluit een handmatige rit af.
        if s.ios.appState == .terminated { await s.appRelaunch() }
        await s.appResume()
        await s.stand(for: 30 * 60)
        try? await s.userTapsStop()
        if mode != .manual { s.assertNoOpenAutomaticTrip(file: file, line: line) }
        try s.assertInvariants(file: file, line: line)
    }

    func testRandomScenarios() async throws {
        for seed in UInt64(1)...UInt64(200) {
            do {
                try await runScenario(seed: seed)
            } catch {
                XCTFail("seed \(seed): \(error)")
            }
            if testRun?.hasBeenSkipped == true { return }
            if testRun.map({ $0.failureCount > 0 }) == true {
                XCTFail("eerste mislukte seed: \(seed)")
                return
            }
        }
    }

    /// Mislukte seeds komen hier als vaste regressietest, bv.:
    /// func testSeed17() async throws { try await runScenario(seed: 17) }
}
```

- [ ] **Step 2: Registreer en draai**

```bash
python3 scripts/add_to_xcodeproj.py ScenarioFuzzTests.swift --like TripRecorderTests.swift
```
Run: `TEST -only-testing:KilometerregistratieTests/ScenarioFuzzTests`
Expected: PASS óf een lijst "eerste mislukte seed: N". Een mislukte seed is een bevinding, geen reden om de invarianten te versoepelen:
1. Voeg `func testSeed<N>() async throws { try await runScenario(seed: N) }` toe zodat de seed vastligt.
2. Maak het scenario handmatig na (de stappen print je met een tijdelijke `print` per stap) en bepaal of het model (`FakeIOS`/runner) of de app fout zit.
3. Zit de fout in de app: stop en rapporteer aan de gebruiker met de seed en de stappenreeks. Zit de fout in het model: repareer het model en documenteer de aanname in `docs/ios-assumptions.md`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "Seed-gestuurde fuzz-test voor ritscenario's

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: iOS-aannamedocument en rooktest voor de adapters

**Files:**
- Create: `docs/ios-assumptions.md`
- Create: `KilometerregistratieTests/ProviderSmokeTests.swift`

**Interfaces:**
- Consumes: `CoreLocationProvider`, `CoreMotionProvider`, `SystemTimeSource` (Taak 1).
- Produces: het document waar elke scenariotest naar verwijst.

- [ ] **Step 1: Schrijf de rooktest**

`KilometerregistratieTests/ProviderSmokeTests.swift`:

```swift
import XCTest
@testable import Kilometerregistratie

/// De echte adapters bevatten geen logica en zijn bewust niet scenario-getest.
/// Deze rooktest bewaakt dat ze aan te maken en te sturen zijn.
@MainActor
final class ProviderSmokeTests: XCTestCase {
    func testCoreLocationProviderCanBeCreatedAndConfigured() {
        let provider = CoreLocationProvider()
        provider.apply(accuracy: 25, distanceFilter: 25)
        provider.startUpdatingLocation()
        provider.stopUpdatingLocation()
        provider.startMonitoringSignificantLocationChanges()
        provider.stopMonitoringSignificantLocationChanges()
        XCTAssertNotNil(provider.authorizationStatus)
    }

    func testCoreMotionProviderStartStopDoesNotCrash() {
        let provider = CoreMotionProvider()
        provider.start { _ in }
        provider.stop()
    }

    func testSystemTimeSourceFiresRepeatedlyAndCancels() async {
        let source = SystemTimeSource()
        var count = 0
        let handle = source.every(0.05) { count += 1 }
        try? await Task.sleep(for: .milliseconds(280))
        handle.cancel()
        let atCancel = count
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThanOrEqual(atCancel, 3)
        XCTAssertEqual(count, atCancel, "na cancel geen vuringen meer")
    }
}
```
Registreer: `python3 scripts/add_to_xcodeproj.py ProviderSmokeTests.swift --like TripRecorderTests.swift`
Run: `TEST -only-testing:KilometerregistratieTests/ProviderSmokeTests` → Expected: PASS.

- [ ] **Step 2: Schrijf `docs/ios-assumptions.md`**

```markdown
# iOS-aannames achter de ritsimulatie

De scenario-tests (`KilometerregistratieTests/ScenarioTests.swift`, `ScenarioFuzzTests.swift`)
draaien op een model van iOS (`Simulation/FakeIOS.swift`). Dit document legt vast wat dat model
aanneemt. Een groene suite bewijst dat **onze logica** klopt onder deze aannames, niet dat iOS
zich zo gedraagt. Elke aanname is daarom een instelbare waarde in `IOSParameters` en heeft een
handmatige controle op een toestel.

**Status:** `zeker` = volgt uit hoe Swift/SwiftData werkt; `Apple-doc` = staat in de
Apple-documentatie, nog te controleren tegen de huidige versie; `te verifiëren` = mijn inschatting,
nog niet gemeten; `meten` = niet gedocumenteerd, waarde moet op een toestel gemeten worden.

| ID | Aanname | Status | Waarde in model | Handmatige controle |
|---|---|---|---|---|
| A0 | Callbacks van CoreLocation komen in volgorde binnen op de main actor. De echte adapter springt via `Task { @MainActor }`, het model levert synchroon af. | zeker | n.v.t. | n.v.t. |
| A1 | `distanceFilter` onderdrukt samples zolang het toestel minder dan die afstand beweegt. | Apple-doc | `FakeLocationProvider.distanceFilter` (25 m standaard) | Laat de telefoon op tafel liggen met een lopende rit en tel de samples in de log. |
| A2 | Met `pausesLocationUpdatesAutomatically` en `.automotiveNavigation` pauzeert iOS de updates na enige tijd stilstand. De duur is niet gedocumenteerd. | meten | `autoPauseAfter` (600 s; fuzz 300 tot 1200 s) | Rit eindigen, telefoon met scherm uit laten liggen, de log laten tonen wanneer de laatste update binnenkwam. |
| A3 | Een opgeschorte app voert geen code uit, ook geen `Task.sleep`-timers. | zeker | `VirtualClock.timersEnabled` | n.v.t. |
| A4 | Hervatten van de updates (beweging na een pauze) maakt een opgeschorte app wakker en levert samples af. | te verifiëren | `wakesWhenUpdatesResume` (aan; fuzz beide) | Na een pauze weer gaan rijden zonder de app te openen; kijk of de rit verder loopt. |
| A5 | Een significante wijziging (ongeveer 500 m) start een beëindigde app opnieuw op de achtergrond. | Apple-doc | `significantChangeDistance` (500 m) | App in de app-schakelaar wegvegen, 1 km rijden, kijken of er een rit ontstaat. |
| A6 | Een beëindigd proces verliest zijn geheugen; de SwiftData-database blijft. | zeker | n.v.t. | n.v.t. |
| A7 | `CLLocation.speed` is `-1` als de snelheid onbekend is. | Apple-doc | `Fix.speed = -1` | Log de snelheid bij een zwakke fix (tunnel, parkeergarage). |
| A8 | `CLLocation.timestamp` is het tijdstip van de fix, niet van de levering; na een pauze kan het oud zijn. | Apple-doc | `Fix.timestamp` (nu altijd gelijk aan virtuele tijd) | Vergelijk `timestamp` met `Date.now` in de log bij het eerste sample na een pauze. |
| A9 | De toestemming intrekken in Instellingen beëindigt de app. | te verifiëren | `revokingPermissionTerminatesApp` (aan) | Tijdens een rit de locatietoestemming op "Nooit" zetten en kijken of het proces stopt. |
| A10 | Bewegingsactiviteit (`CMMotionActivity`) is verouderd na opschorten. | te verifiëren | niet gemodelleerd; `FakeMotionProvider.send` laat tests het nabootsen | Bij een rit na een lange pauze loggen wanneer de laatste activiteit binnenkwam. |

## Wat het model bewust niet doet

- Geen batterij- of thermische beperkingen, geen "Low Power Mode".
- Geen systeemdialogen of ontbrekende toestemming "Bij gebruik" versus "Altijd" op de achtergrond
  (de service krijgt altijd `.authorizedAlways`, behalve bij het intrekken).
- Geen netwerk (`FakeAddressResolver` geeft altijd hetzelfde adres).

## Een aanname bijwerken

1. Meet of lees het echte gedrag.
2. Pas de status en de waarde in deze tabel aan.
3. Pas `IOSParameters` of `FakeIOS` aan en draai `ScenarioTests` en `ScenarioFuzzTests`.
4. Een scenario dat daardoor faalt, laat een echte bug zien. Repareer de app, niet de aanname.
```

- [ ] **Step 3: Draai de volledige suite**

Run: `TEST`
Expected: PASS, alle tests groen.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "iOS-aannamedocument en rooktest voor de echte adapters

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage.** Hoofdstuk 3 (protocollen) en 4 (service) → Taak 1. Hoofdstuk 5 (VirtualClock, fakes, FakeIOS, RoutePlayer, ScenarioRunner) → Taak 2 en 3; het RoutePlayer-gedrag zit als `drive`/`stand`/`jump`/`wait` in `ScenarioRunner` in plaats van een apart type (bewuste vereenvoudiging, geen aparte verantwoordelijkheid). Hoofdstuk 6 (invarianten 1 t/m 6, fuzz) → Taak 3 (invarianten) en Taak 5. Hoofdstuk 7 (aannames A0 t/m A10) → Taak 6; elke scenariotest noemt zijn aannames. Hoofdstuk 9 volgorde: gevolgd. Hoofdstuk 8 (rooktest, risico's) → Taak 6. De spec noemt `app.opschorten()` e.d. als stappen; in de runner heten ze `appSuspend()` enz., en `gebruiker.tiktStart()` is `userTapsStart()`.

**Placeholders.** Geen "TBD"/"TODO"; elke code-stap bevat de code. Taak 1 Step 5 beschrijft vervangingen als lijst met exacte regels (omdat de service 570 regels telt); elke vervanging noemt de oude en de nieuwe tekst.

**Type consistency.** `TimerHandle`, `TimeSource.every`, `LocationProviding` (tien methoden), `MotionProviding.start(handler:)`, `AddressResolving.address(latitude:longitude:context:)`, `VirtualClock.advance(to:)/resumeTimers()/removeAllTimers()/timersEnabled`, `FakeIOS.offer/goToBackground/suspend/resume/terminate`, `ScenarioRunner`-stappen en `assertInvariants`/`assertNoOpenAutomaticTrip` zijn in elke taak met dezelfde namen en signaturen gebruikt. `TripRecorder(now:)` is in Taak 3 Step 1 gedefinieerd en daarna gebruikt.

**Review Focus gedekt.** Opgeschorte app die nooit opent: `testSuspendedAppKeepsTripOpenUntilUserOpensApp` (Taak 3). Handmatig in hybride: `testHybridManualTripIsNotDuplicatedByDetection` (Taak 4). Kill en herstel binnen/na 30 min: `testKillDuringTripThenQuickRelaunchResumesWithRoute` (Taak 3) en `testKillThenLateRelaunchFinalizesAtLastKnownActivity` (Taak 4). Toestemming ingetrokken: `testPermissionRevokedDuringTripLeavesNoOpenTrip` (Taak 4). Gat met rijsnelheid erna: `testFastSampleAfterLongGapStartsNewTripInsteadOfExtendingOldOne` (Taak 4).

**Bekende onzekerheden** (voor wie dit uitvoert):
- De scenario's zijn ontworpen, nog niet gedraaid. Een rood scenario kan een fout in `FakeIOS`/runner zijn of een echte app-bug; Taak 3 Step 7 en Taak 5 Step 2 beschrijven hoe je dat onderscheidt.
- `settle()` gebruikt 20 keer `Task.yield()`. Als een scenario flakey blijkt, verhoog dat getal of wacht op een expliciete conditie.
- De invarianten gebruiken een tolerantie van 3% + 100 m en een marge van 91 s boven de drempel; strakker maken kan pas na de eerste groene run.
