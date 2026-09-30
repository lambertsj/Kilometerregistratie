import Foundation

/// Lichtgewicht weergave van een rit voor validatie, losgekoppeld van
/// SwiftData zodat de controle pure, testbare logica blijft.
struct TripValidationInput: Equatable {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var startOdometer: Double?
    var endOdometer: Double?
    var distanceKm: Double
    var category: TripCategory
    var vehicleID: UUID?
    /// De ingevulde waarde per veld; ontbrekend of leeg telt als niet ingevuld.
    var fieldValues: [TripField: String]

    init(
        id: UUID,
        startDate: Date,
        endDate: Date? = nil,
        startOdometer: Double? = nil,
        endOdometer: Double? = nil,
        distanceKm: Double = 0,
        category: TripCategory = .business,
        vehicleID: UUID? = nil,
        fieldValues: [TripField: String] = [:]
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.startOdometer = startOdometer
        self.endOdometer = endOdometer
        self.distanceKm = distanceKm
        self.category = category
        self.vehicleID = vehicleID
        self.fieldValues = fieldValues
    }
}

enum IssueSeverity: String, Equatable, Comparable, Sendable {
    /// De registratie is op dit punt aantoonbaar niet sluitend of onvolledig.
    case blocking
    /// Opvallend, maar niet per se fout.
    case warning

    private var order: Int {
        switch self {
        case .blocking: 0
        case .warning: 1
        }
    }

    static func < (lhs: IssueSeverity, rhs: IssueSeverity) -> Bool {
        lhs.order < rhs.order
    }
}

/// Wat er aan de registratie mankeert. Bewust beschrijvend geformuleerd: de
/// app stelt vast wát er in het dossier ontbreekt of niet aansluit, en doet
/// geen uitspraak over wat een belastingdienst daarvan zou vinden.
enum LogIssueKind: Equatable, Sendable {
    /// Tussen twee opeenvolgende ritten zit een niet-verantwoord aantal
    /// kilometers.
    case odometerGap(km: Double)
    /// De beginstand van een rit ligt vóór de eindstand van de vorige.
    case odometerOverlap(km: Double)
    /// Een rit mist een kilometerstand die voor een sluitende reeks nodig is.
    case missingOdometer(TripField)
    /// De afstand van de rit komt niet overeen met het verschil tussen de
    /// kilometerstanden.
    case distanceMismatch(odometerKm: Double, recordedKm: Double)
    /// Een voor deze categorie verplicht veld is niet ingevuld.
    case missingRequiredField(TripField)
    /// De rit heeft geen voertuig, waardoor hij niet in een sluitende reeks
    /// past.
    case missingVehicle
    /// De rit is nooit afgesloten.
    case unfinishedTrip
}

struct LogIssue: Equatable, Identifiable, Sendable {
    var id: UUID
    var severity: IssueSeverity
    var kind: LogIssueKind
    /// De rit(ten) waar het om gaat. Bij een gat of overlap zijn dat er twee,
    /// in chronologische volgorde.
    var tripIDs: [UUID]
    /// De rit waar de gebruiker naartoe moet springen.
    var primaryTripID: UUID? { tripIDs.last }

    init(severity: IssueSeverity, kind: LogIssueKind, tripIDs: [UUID], id: UUID = UUID()) {
        self.id = id
        self.severity = severity
        self.kind = kind
        self.tripIDs = tripIDs
    }
}

/// Eén samengevatte toestand voor een periode, voor een koptekst boven de
/// issuelijst. Puur afgeleid van de issues zelf — geen eigen oordeel.
enum LogHeadlineState: Equatable, Sendable {
    /// Geen enkele melding.
    case ok
    /// Alleen waarschuwingen: niets blokkerends, maar het valt op.
    case warnings(count: Int)
    /// Ten minste één blokkerende melding: de registratie is op dit punt
    /// aantoonbaar niet sluitend of onvolledig.
    case blocking(count: Int, warningCount: Int)

    init(issues: [LogIssue]) {
        let blockingCount = issues.count { $0.severity == .blocking }
        let warningCount = issues.count { $0.severity == .warning }
        if blockingCount > 0 {
            self = .blocking(count: blockingCount, warningCount: warningCount)
        } else if warningCount > 0 {
            self = .warnings(count: warningCount)
        } else {
            self = .ok
        }
    }
}

/// Controleert of een registratie sluitend en volledig is volgens de regels
/// van de ingestelde regio.
///
/// Gaten worden nooit stilzwijgend gedicht: ze worden gerapporteerd.
enum LogValidator {
    /// Marge waarbinnen een verschil in kilometerstanden als afronding geldt
    /// in plaats van als gat. Kilometerstanden worden per hele kilometer
    /// genoteerd, afstanden met een decimaal.
    static let toleranceKm = 1.0

    static func validate(
        trips: [TripValidationInput],
        ruleSet: any RegionRuleSet
    ) -> [LogIssue] {
        var issues: [LogIssue] = []

        for trip in trips {
            issues.append(contentsOf: fieldIssues(for: trip, ruleSet: ruleSet))
        }

        if ruleSet.enforcesOdometerContinuity {
            issues.append(contentsOf: continuityIssues(for: trips))
        }

        // Blokkerend eerst, daarbinnen op datum: dat is de volgorde waarin een
        // gebruiker ze wil aflopen.
        let order = Dictionary(uniqueKeysWithValues: trips.enumerated().map { ($0.element.id, $0.offset) })
        return issues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            return (order[lhs.primaryTripID ?? UUID()] ?? 0) < (order[rhs.primaryTripID ?? UUID()] ?? 0)
        }
    }

    // MARK: - Verplichte velden

    private static func fieldIssues(
        for trip: TripValidationInput,
        ruleSet: any RegionRuleSet
    ) -> [LogIssue] {
        var issues: [LogIssue] = []
        let required = ruleSet.requiredFields(for: trip.category)

        for field in required.sorted(by: { $0.rawValue < $1.rawValue }) {
            if isMissing(field, in: trip) {
                let kind: LogIssueKind = (field == .startOdometer || field == .endOdometer)
                    ? .missingOdometer(field)
                    : .missingRequiredField(field)
                issues.append(LogIssue(severity: .blocking, kind: kind, tripIDs: [trip.id]))
            }
        }

        if trip.endDate == nil {
            issues.append(LogIssue(severity: .warning, kind: .unfinishedTrip, tripIDs: [trip.id]))
        }

        if ruleSet.enforcesOdometerContinuity, trip.vehicleID == nil {
            issues.append(LogIssue(severity: .blocking, kind: .missingVehicle, tripIDs: [trip.id]))
        }

        // Klopt de eigen afstand met de eigen kilometerstanden? Een groter
        // verschil wijst op een niet genoteerde omweg.
        if let start = trip.startOdometer, let end = trip.endOdometer {
            let odometerKm = end - start
            if abs(odometerKm - trip.distanceKm) > toleranceKm {
                issues.append(
                    LogIssue(
                        severity: .warning,
                        kind: .distanceMismatch(odometerKm: odometerKm, recordedKm: trip.distanceKm),
                        tripIDs: [trip.id]
                    )
                )
            }
        }

        return issues
    }

    private static func isMissing(_ field: TripField, in trip: TripValidationInput) -> Bool {
        switch field {
        case .date:
            return false // een rit heeft altijd een datum
        case .distance:
            return trip.distanceKm <= 0
        case .startOdometer:
            return trip.startOdometer == nil
        case .endOdometer:
            return trip.endOdometer == nil
        case .startAddress, .endAddress, .destinationPlace, .destinationStreet,
             .purpose, .businessPartner, .detourNote, .annotation:
            let value = trip.fieldValues[field] ?? ""
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Sluitende kilometerreeks

    /// Loopt de ritten per voertuig in chronologische volgorde af en meldt
    /// gaten en overlappen. Vult niets aan.
    private static func continuityIssues(for trips: [TripValidationInput]) -> [LogIssue] {
        var issues: [LogIssue] = []
        let byVehicle = Dictionary(grouping: trips.filter { $0.vehicleID != nil }) { $0.vehicleID! }

        for (_, vehicleTrips) in byVehicle.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let ordered = vehicleTrips.sorted { $0.startDate < $1.startDate }
            for (previous, current) in zip(ordered, ordered.dropFirst()) {
                guard let previousEnd = previous.endOdometer,
                      let currentStart = current.startOdometer else { continue }

                let difference = currentStart - previousEnd
                if difference > toleranceKm {
                    issues.append(
                        LogIssue(
                            severity: .blocking,
                            kind: .odometerGap(km: difference),
                            tripIDs: [previous.id, current.id]
                        )
                    )
                } else if difference < -toleranceKm {
                    issues.append(
                        LogIssue(
                            severity: .blocking,
                            kind: .odometerOverlap(km: -difference),
                            tripIDs: [previous.id, current.id]
                        )
                    )
                }
            }
        }
        return issues
    }
}
