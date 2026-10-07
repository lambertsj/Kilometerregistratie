import Foundation
import CoreLocation
import CoreMotion
import SwiftData
import Observation

/// CoreLocation-laag: route-opname tijdens handmatige ritten en automatische
/// ritdetectie (hybride/automatische modus).
///
/// Batterij-afweging, bewust gekozen en hier gedocumenteerd — dit is een
/// bewuste twee-traps-aanpak, nergens draait permanente high-accuracy
/// tracking:
/// - In rust luistert de app alléén naar significant location changes
///   (celtoren-niveau, verwaarloosbaar batterijverbruik). Zodra daar
///   rijsnelheid uit blijkt, schakelen we naar continue high-accuracy
///   updates — alleen tijdens een bevestigde rit.
/// - Binnen die continue updates is er nog een keuze tussen nauwkeurigheid
///   en batterij, instelbaar via `AppSettings.locationAccuracyPreference`
///   (zie `applyAccuracyPreference`): `.balanced` (standaard,
///   `kCLLocationAccuracyNearestTenMeters` / 25 m) is de beste afweging voor
///   de meeste ritten; `.precise` (`.best` / 10 m) kost merkbaar meer
///   energie voor een nauwkeurigere route; `.batterySaver`
///   (`.hundredMeters` / 50 m) verlengt de accuduur maar maakt de route en
///   afstand iets grover — vandaar ook een ruimere GPS-ruisdrempel in die
///   stand (zie `GPSPointFilter`).
/// - `pausesLocationUpdatesAutomatically` + `activityType = .automotiveNavigation`
///   laat iOS de GPS uitzetten bij langdurige stilstand.
/// - Na afloop van een rit stoppen de continue updates direct; alleen de
///   significant-change-monitor blijft actief.
@Observable
@MainActor
final class LocationTrackingService: NSObject {
    enum RecordingSource: Equatable {
        case manual
        case automatic
    }

    private let manager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()
    private var modelContext: ModelContext?
    private var detector = TripDetector()
    private let geocoder = GeocodingService()

    /// Meest recente CoreMotion-classificatie; gebruikt door
    /// `MotionActivityGate` om te voorkomen dat OV of fietsen (die toevallig
    /// de snelheidsdrempel halen) een automatische rit starten.
    private var latestActivity: MotionActivityGate.ActivitySample?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var recordingSource: RecordingSource?
    /// Live afstand van de lopende opname, voor weergave op het hoofdscherm.
    private(set) var liveDistanceKm: Double = 0

    enum LocationIssue: Equatable {
        /// Toestemming is tijdens een lopende opname ingetrokken (bv. omdat
        /// de gebruiker die zelf via Instellingen heeft verlaagd). De rit is
        /// automatisch afgesloten op de laatst bekende positie; dit moet de
        /// gebruiker expliciet zien in plaats van dat registratie
        /// stilletjes stopt.
        case permissionRevokedDuringRecording
        /// Locatievoorzieningen staan systeemwide uit (Instellingen >
        /// Privacy en beveiliging), los van de toestemming van deze app.
        case locationServicesDisabled
    }

    /// Actuele, aan de gebruiker te tonen locatie-fout. Tijdelijke
    /// GPS-uitval (tunnel, parkeergarage) zit hier bewust niet in — dat
    /// herstelt zichzelf en zou alleen maar onnodig verontrusten.
    private(set) var currentIssue: LocationIssue?

    /// Verbergt de huidige melding nadat de gebruiker deze heeft gezien.
    func dismissIssue() {
        currentIssue = nil
    }

    /// Automatisch afgesloten rit die nog niet geclassificeerd is. Zonder
    /// dit zou een automatisch gedetecteerde rit stilzwijgend op de
    /// standaardcategorie blijven staan — de gebruiker moet de kans krijgen
    /// om 'm in één tik te classificeren, net als bij handmatige ritten.
    private(set) var pendingClassificationTrip: Trip?

    /// Onder deze afstand vragen we niet om classificatie: te kort om een
    /// zinvolle rit te zijn (bv. een enkel GPS-punt dat net de
    /// motion-gate/snelheidsdrempel haalde).
    private static let minimumDistanceForClassificationKm = 0.5

    func clearPendingClassification() {
        pendingClassificationTrip = nil
    }

    private var recordingTrip: Trip?
    private var routePoints: [RoutePoint] = []
    private var routeStartDate: Date?
    private var detectionEnabled = false

    /// Laatst geaccepteerde (dus niet per se laatst binnengekomen) sample,
    /// referentiepunt voor `GPSPointFilter` om de volgende sample op
    /// nauwkeurigheid en fysiek plausibele snelheid te beoordelen.
    private var lastAcceptedSample: GPSPointFilter.Sample?
    private var maxHorizontalAccuracy = GPSPointFilter.defaultMaxHorizontalAccuracy

    /// Laatste moment waarop een locatiesample is binnengekomen tijdens een
    /// opname; de watchdog gebruikt dit om te zien of CoreLocation zelf is
    /// gestopt met leveren (in tegenstelling tot `TripDetector`, die alleen
    /// binnen inkomende samples kan beslissen).
    private var lastSampleAt: Date?
    private var recordingStartedAt: Date?
    private var watchdogTask: Task<Void, Never>?

    /// Zoveel seconden (op sample-tijd) tussen twee tussentijdse schrijfacties
    /// van de route. Zonder dit staat de route alleen in het geheugen en weet
    /// `resumeIfNeeded` na een kill niet meer wanneer de rit voor het laatst
    /// leefde.
    private static let routePersistInterval: TimeInterval = 60
    private var lastRoutePersistAt: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = true
        authorizationStatus = manager.authorizationStatus
    }

    func configure(context: ModelContext) {
        modelContext = context
    }

    // MARK: - Autorisatie

    var canUseLocation: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Rit die op toestemming wacht: `requestWhenInUseAuthorization()` is
    /// asynchroon (toont de systeemdialoog en keert direct terug, ruim
    /// vóórdat de gebruiker heeft geantwoord). Zonder dit zou de eerste
    /// STARTs na installatie geen route opnemen, zelfs niet als de
    /// gebruiker toestemming geeft — `beginRouteRecording` zou al voorbij
    /// zijn op het moment dat `canUseLocation` waar wordt.
    private var awaitingAuthorizationTrip: Trip?

    /// Voor automatische detectie op de achtergrond is "Altijd" nodig.
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Instellingen toepassen

    /// Zet automatische detectie aan/uit op basis van de registratiemodus.
    func applySettings(_ settings: AppSettings) {
        detector.stopAfterStationaryInterval = TimeInterval(settings.autoStopThresholdMinutes * 60)
        applyAccuracyPreference(settings.locationAccuracyPreference)
        let wantsDetection = settings.trackingMode != .manual
        guard wantsDetection != detectionEnabled else { return }
        detectionEnabled = wantsDetection

        if wantsDetection {
            manager.startMonitoringSignificantLocationChanges()
            // Continue updates starten pas zodra er rijsnelheid gezien wordt.
            startMotionUpdatesIfAvailable()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
            stopMotionUpdates()
            detector.reset()
            if recordingSource == .automatic {
                Task { await stopRecording(endDate: .now) }
            }
        }
    }

    /// Past `desiredAccuracy`/`distanceFilter` en de bijbehorende
    /// GPS-ruisdrempel toe op basis van de gekozen batterij-afweging. Zie
    /// de documentatie bovenaan dit bestand voor de volledige afweging.
    private func applyAccuracyPreference(_ preference: LocationAccuracyPreference) {
        switch preference {
        case .batterySaver:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 50
            maxHorizontalAccuracy = 120
        case .balanced:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 25
            maxHorizontalAccuracy = GPSPointFilter.defaultMaxHorizontalAccuracy
        case .precise:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 10
            maxHorizontalAccuracy = 30
        }
    }

    // MARK: - CoreMotion

    private func startMotionUpdatesIfAvailable() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            self.latestActivity = MotionActivityGate.ActivitySample(
                automotive: activity.automotive,
                confidence: MotionActivityGate.ActivitySample.Confidence(activity.confidence)
            )
        }
    }

    private func stopMotionUpdates() {
        motionActivityManager.stopActivityUpdates()
        latestActivity = nil
    }

    // MARK: - Route-opname

    /// Start route-opname voor een handmatig gestarte rit. Als toestemming
    /// nog niet gevraagd is, wordt de systeemdialoog getoond en start de
    /// opname alsnog zodra `handleAuthorizationChange` toestemming ziet.
    func beginRouteRecording(for trip: Trip) {
        guard recordingTrip == nil else { return }
        if canUseLocation {
            startRecording(trip: trip, source: .manual)
        } else if authorizationStatus == .notDetermined {
            awaitingAuthorizationTrip = trip
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Rondt de lopende opname af: schrijft route, afstand, coördinaten en
    /// (via reverse geocoding met cache) adressen naar de rit.
    func stopRecording(endDate: Date) async {
        guard let trip = recordingTrip else { return }
        let wasAutomatic = recordingSource == .automatic
        stopContinuousUpdates()

        let points = routePoints
        recordingTrip = nil
        recordingSource = nil
        routePoints = []
        liveDistanceKm = 0
        lastSampleAt = nil
        recordingStartedAt = nil
        lastAcceptedSample = nil
        lastRoutePersistAt = nil

        guard let context = modelContext else { return }
        let writer = TripWriteService(context: context)

        _ = try? writer.update(trip) { trip in
            // Automatische ritten sluit alleen de service zelf af. Een
            // handmatige rit krijgt zijn einddatum van `TripRecorder.stop`,
            // zodat dat niet als wijziging achteraf geldt.
            if wasAutomatic { trip.endDate = endDate }
            if points.count >= 2 {
                trip.routeData = try? RoutePolyline.encode(points)
                trip.distanceKm = GeoDistance.routeDistanceKm(points)
            }
            if let first = points.first {
                trip.startLatitude = first.latitude
                trip.startLongitude = first.longitude
            }
            if let last = points.last {
                trip.endLatitude = last.latitude
                trip.endLongitude = last.longitude
            }
        }

        // Reverse geocoding gebeurt asynchroon; de adressen worden daarna in
        // één keer weggeschreven.
        var resolvedStart: String?
        var resolvedEnd: String?
        if let first = points.first {
            resolvedStart = await geocoder.address(latitude: first.latitude, longitude: first.longitude, context: context)
        }
        if let last = points.last {
            resolvedEnd = await geocoder.address(latitude: last.latitude, longitude: last.longitude, context: context)
        }
        _ = try? writer.update(trip) { trip in
            if let resolvedStart { trip.startAddress = resolvedStart }
            if let resolvedEnd { trip.endAddress = resolvedEnd }
        }

        if wasAutomatic, trip.distanceKm >= Self.minimumDistanceForClassificationKm {
            applySuggestedCategory(to: trip, context: context)
            pendingClassificationTrip = trip
        }
    }

    /// Vult alvast de zelflerende/kantooruren-suggestie in, net als bij het
    /// afrondformulier voor handmatige ritten, zodat de rit ook zonder actie
    /// van de gebruiker een zinvolle categorie heeft — het één-tik-scherm
    /// laat de gebruiker die daarna bevestigen of aanpassen.
    private func applySuggestedCategory(to trip: Trip, context: ModelContext) {
        var learned: TripCategory?
        if let key = TripClassifier.routeKey(startAddress: trip.startAddress, endAddress: trip.endAddress) {
            learned = ClassificationRuleRepository(context: context).learnedCategory(forRouteKey: key)
        }
        let settings = AppSettings.fetchOrCreate(in: context)
        let suggested = TripClassifier.suggestCategory(startDate: trip.startDate, learned: learned, schedule: settings.workSchedule)
        _ = try? TripWriteService(context: context).update(trip) { $0.category = suggested }
    }

    /// Breekt de opname af zonder iets naar de rit te schrijven
    /// (gebruikt wanneer de gebruiker de rit annuleert).
    func cancelRecording() {
        guard recordingTrip != nil else { return }
        stopContinuousUpdates()
        recordingTrip = nil
        recordingSource = nil
        routePoints = []
        liveDistanceKm = 0
        lastSampleAt = nil
        recordingStartedAt = nil
        lastAcceptedSample = nil
        lastRoutePersistAt = nil
    }

    /// Hervat een opname na een app-herstart, voor een rit die nog "actief"
    /// (endDate == nil) in de database staat. Zonder dit blijft zo'n rit
    /// voor altijd hangen als de app tijdens het rijden is gekilld.
    /// Beslist via `HangingTripRecovery` of hervatten nog zinvol is, of dat
    /// de rit direct afgesloten moet worden omdat er te veel tijd zonder
    /// teken van leven is verstreken.
    func resumeIfNeeded(context: ModelContext, now: Date = .now) async {
        guard recordingTrip == nil else { return }
        guard let trip = try? TripRepository(context: context).activeTrip() else { return }

        let existingPoints = trip.routeData.flatMap { try? RoutePolyline.decode($0) } ?? []
        let lastKnownActivity = existingPoints.last.map { trip.startDate.addingTimeInterval($0.offset) } ?? trip.startDate

        switch HangingTripRecovery.decide(lastKnownActivity: lastKnownActivity, now: now) {
        case .resume:
            guard canUseLocation else { return }
            recordingTrip = trip
            recordingSource = trip.isAutomaticallyRecorded ? .automatic : .manual
            routePoints = existingPoints
            routeStartDate = trip.startDate
            liveDistanceKm = GeoDistance.routeDistanceKm(existingPoints)
            recordingStartedAt = trip.startDate
            lastSampleAt = now
            lastAcceptedSample = existingPoints.last.map { Self.sample(from: $0, routeStartDate: trip.startDate) }
            lastRoutePersistAt = nil
            if trip.isAutomaticallyRecorded {
                detector.reset()
            }
            beginContinuousUpdates()

        case .finalize(let endDate):
            _ = try? TripWriteService(context: context).update(trip) { $0.endDate = endDate }
        }
    }

    func startRecording(trip: Trip, source: RecordingSource) {
        recordingTrip = trip
        recordingSource = source
        routePoints = []
        routeStartDate = trip.startDate
        liveDistanceKm = 0
        recordingStartedAt = trip.startDate
        lastSampleAt = .now
        lastAcceptedSample = nil
        lastRoutePersistAt = nil
        currentIssue = nil
        beginContinuousUpdates()
    }

    private static func sample(from point: RoutePoint, routeStartDate: Date) -> GPSPointFilter.Sample {
        GPSPointFilter.Sample(
            latitude: point.latitude, longitude: point.longitude,
            horizontalAccuracy: 0, timestamp: routeStartDate.addingTimeInterval(point.offset)
        )
    }

    private func beginContinuousUpdates() {
        // Achtergrond-updates zijn nodig om de rit door te meten als het
        // toestel in de zak/houder zit; de blauwe indicator maakt dit
        // transparant voor de gebruiker.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        startWatchdog()
    }

    private func stopContinuousUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    /// Onafhankelijk van binnenkomende locatiesamples: sluit een opname
    /// alsnog af als CoreLocation zelf stopt met leveren (auto-pause,
    /// achtergrondlimiet, tunnel) of als een rit een onredelijk lange tijd
    /// doorloopt. `TripDetector` alleen kan dit niet, want die beslist enkel
    /// op basis van samples die binnenkomen.
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.checkWatchdog()
            }
        }
    }

    /// Draait ook zodra de app weer actief wordt: een opgeschorte app voert
    /// de timer hierboven niet uit, dus zonder deze aanroep blijft een rit
    /// open staan totdat de timer toevallig weer loopt.
    func checkWatchdog(now: Date = .now) async {
        guard recordingTrip != nil,
              let startedAt = recordingStartedAt,
              let lastSample = lastSampleAt else { return }
        let watchdog = RecordingWatchdog(stopAfterStationaryInterval: detector.stopAfterStationaryInterval)
        guard watchdog.shouldForceStop(
            recordingStartedAt: startedAt,
            lastSampleAt: lastSample,
            now: now,
            ignoreGPSSilence: recordingSource == .manual
        ) else { return }
        detector.reset()
        await stopRecording(endDate: lastSample)
    }

    // MARK: - Samples verwerken

    fileprivate func handleAuthorizationChange() {
        authorizationStatus = manager.authorizationStatus
        if !canUseLocation, recordingTrip != nil {
            currentIssue = .permissionRevokedDuringRecording
            Task { await stopRecording(endDate: .now) }
        }
        if let trip = awaitingAuthorizationTrip, authorizationStatus != .notDetermined {
            awaitingAuthorizationTrip = nil
            if canUseLocation, recordingTrip == nil {
                startRecording(trip: trip, source: .manual)
            }
        }
    }

    func handle(locations: [CLLocation]) {
        currentIssue = nil
        for location in locations {
            let event: TripDetector.Event
            if detectionEnabled {
                event = detector.process(TripDetector.Sample(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    speed: location.speed,
                    timestamp: location.timestamp
                ))
            } else {
                event = .none
            }

            // Een sample dat een automatische rit beëindigt (bv. het eerste na
            // een lang gat) hoort niet meer bij die rit: anders telt de afstand
            // over het gat mee.
            let endsAutomaticTrip: Bool
            if case .tripEnded = event, recordingSource == .automatic {
                endsAutomaticTrip = true
            } else {
                endsAutomaticTrip = false
            }
            if recordingTrip != nil, !endsAutomaticTrip {
                lastSampleAt = location.timestamp
                appendRoutePoint(from: location)
            }
            guard detectionEnabled else { continue }

            switch event {
            case .none:
                // Wakker geworden door significant change zonder rijsnelheid:
                // even continue updates aanzetten om snelheid te peilen zou
                // batterij kosten; we wachten op een sample mét snelheid.
                break

            case .tripStarted:
                guard recordingTrip == nil, let context = modelContext else { break }
                // Geen dubbele registratie naast een handmatig gestarte rit.
                guard (try? TripRepository(context: context).activeTrip()) == nil else { break }
                // OV/fietsen kunnen toevallig de snelheidsdrempel halen; laat
                // CoreMotion die gevallen wegfilteren. Detector terugzetten
                // naar idle zodat een latere, echte rit gewoon opnieuw
                // getriggerd kan worden.
                guard MotionActivityGate.allowsAutomaticStart(latestActivity) else {
                    detector.reset()
                    break
                }
                let repository = TripRepository(context: context)
                if let previous = try? repository.mostRecentAutomaticTrip(),
                   let previousEnd = previous.endDate,
                   AutomaticTripMerge.shouldMerge(previousTripEndDate: previousEnd, newTripStartDate: location.timestamp) {
                    // Korte onderbreking (bv. een treinstop): ga door met de
                    // vorige rit in plaats van een nieuwe aan te maken.
                    resumeRecording(reopening: previous, at: location)
                } else {
                    let trip = Trip(
                        startDate: location.timestamp,
                        isAutomaticallyRecorded: true
                    )
                    try? TripWriteService(context: context).create(trip)
                    startRecording(trip: trip, source: .automatic)
                    appendRoutePoint(from: location)
                }

            case .tripEnded(let endDate):
                if recordingSource == .automatic, recordingTrip != nil {
                    Task { await stopRecording(endDate: endDate) }
                }
            }
        }
    }

    /// Heropent een net afgesloten automatische rit om een korte
    /// onderbreking (bv. een treinstop) te overbruggen in plaats van een
    /// aparte nieuwe rit aan te maken; zie `AutomaticTripMerge`.
    private func resumeRecording(reopening trip: Trip, at location: CLLocation) {
        // Rit wordt weer actief: niet meer om classificatie vragen totdat
        // hij (opnieuw) écht afgesloten wordt.
        if pendingClassificationTrip?.id == trip.id {
            pendingClassificationTrip = nil
        }
        let existingPoints = trip.routeData.flatMap { try? RoutePolyline.decode($0) } ?? []
        // Een al afgesloten rit wordt hier heropend. Dat is een wijziging aan
        // een vastgelegde rit en gaat dus via de schrijfservice, zodat hij in
        // een regio met bewaarplicht in de audit trail terechtkomt.
        if let context = modelContext {
            _ = try? TripWriteService(context: context).update(trip) { $0.endDate = nil }
        } else {
            trip.endDate = nil
        }
        recordingTrip = trip
        recordingSource = .automatic
        routePoints = existingPoints
        routeStartDate = trip.startDate
        liveDistanceKm = GeoDistance.routeDistanceKm(existingPoints)
        recordingStartedAt = trip.startDate
        lastSampleAt = location.timestamp
        lastAcceptedSample = existingPoints.last.map { Self.sample(from: $0, routeStartDate: trip.startDate) }
        lastRoutePersistAt = nil
        beginContinuousUpdates()
        appendRoutePoint(from: location)
    }

    private func appendRoutePoint(from location: CLLocation) {
        let sample = GPSPointFilter.Sample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        // Verwerpt te onnauwkeurige metingen en fysiek onmogelijke sprongen
        // (bv. een GPS-glitch in een tunnel of parkeergarage) vóórdat ze de
        // afstand van de rit kunnen vertekenen.
        guard GPSPointFilter.accepts(sample, previous: lastAcceptedSample, maxHorizontalAccuracy: maxHorizontalAccuracy) else { return }
        lastAcceptedSample = sample

        let start = routeStartDate ?? location.timestamp
        let point = RoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            offset: location.timestamp.timeIntervalSince(start)
        )
        if let previous = routePoints.last {
            liveDistanceKm += GeoDistance.meters(
                fromLatitude: previous.latitude, longitude: previous.longitude,
                toLatitude: point.latitude, longitude: point.longitude
            ) / 1000
        }
        routePoints.append(point)
        persistRouteIfDue(at: location.timestamp)
    }

    /// Schrijft de route tussentijds weg, hooguit eens per interval. Dit is
    /// het opbouwen van een lopende rit en geeft dus geen audit-revisie.
    private func persistRouteIfDue(at timestamp: Date) {
        if let last = lastRoutePersistAt, timestamp.timeIntervalSince(last) < Self.routePersistInterval { return }
        guard let trip = recordingTrip, let context = modelContext,
              let data = try? RoutePolyline.encode(routePoints) else { return }
        lastRoutePersistAt = timestamp
        _ = try? TripWriteService(context: context).update(trip) { $0.routeData = data }
    }
}

extension LocationTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            handleAuthorizationChange()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            handle(locations: locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Tijdelijke GPS-uitval is normaal (tunnel, parkeergarage); de
        // detector en route-opname herstellen zodra er weer samples komen.
        // Alleen het systeemwide uitschakelen van locatievoorzieningen tonen
        // we aan de gebruiker, want dat registreert helemaal niets meer
        // totdat de gebruiker het zelf weer aanzet.
        guard (error as? CLError)?.code == .denied, !CLLocationManager.locationServicesEnabled() else { return }
        Task { @MainActor in
            self.currentIssue = .locationServicesDisabled
        }
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
