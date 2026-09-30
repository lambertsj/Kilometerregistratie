import Foundation
import SwiftData

/// De enige plek waar ritten aangemaakt, gewijzigd of verwijderd worden.
///
/// Waarom één doorgang: een regio met bewaarplicht (Duitsland) eist dat elke
/// latere wijziging vastgelegd én bewaard blijft. Een rit die ergens anders
/// rechtstreeks aangepast kan worden, ondermijnt dat volledig. Daarom loopt
/// élke schrijfactie via `create`, `update` of `delete` hier, en staat er in
/// de views en services geen `trip.x = y` meer.
///
/// De revisies worden alleen geschreven als de regelset ze vraagt; voor
/// Nederland gedraagt deze service zich exact als de oude repository —
/// inclusief het echt verwijderen van een rit.
struct TripWriteService {
    let context: ModelContext
    let ruleSet: any RegionRuleSet
    /// Injecteerbaar zodat tests het tijdstip van een wijziging kunnen sturen.
    var now: () -> Date = { .now }

    init(context: ModelContext, ruleSet: any RegionRuleSet, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.ruleSet = ruleSet
        self.now = now
    }

    /// Handige initializer die de regio uit de opgeslagen instellingen leest.
    init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.init(
            context: context,
            ruleSet: AppSettings.fetchOrCreate(in: context).ruleSet,
            now: now
        )
    }

    // MARK: - Aanmaken

    func create(_ trip: Trip) throws {
        context.insert(trip)
        if ruleSet.requiresAuditTrail {
            appendRevision(
                tripID: trip.id,
                tripStartDate: trip.startDate,
                kind: .created,
                field: nil,
                previousValue: "",
                newValue: ""
            )
        }
        try context.save()
    }

    // MARK: - Wijzigen

    /// Voert een wijziging uit en legt vast wat er veranderd is.
    ///
    /// De aanroeper past de rit aan binnen de closure; deze functie maakt vóór
    /// en ná een momentopname en bepaalt daaruit zelf welke velden gewijzigd
    /// zijn. Zo kan een aanroeper geen veld "vergeten" te melden.
    @discardableResult
    func update(_ trip: Trip, _ changes: (Trip) -> Void) throws -> [TripRevision] {
        let before = TripSnapshot(trip)
        changes(trip)
        let after = TripSnapshot(trip)

        var revisions: [TripRevision] = []
        // Zolang de rit nog loopt is dit het opbouwen van de registratie (de
        // GPS-opname schrijft route, afstand en adressen weg), geen wijziging
        // achteraf. Pas een afgesloten rit levert revisies op.
        if ruleSet.requiresAuditTrail, before.isFinalised {
            for change in before.changes(to: after) {
                revisions.append(
                    appendRevision(
                        tripID: trip.id,
                        tripStartDate: trip.startDate,
                        kind: .updated,
                        field: change.field,
                        previousValue: change.previousValue,
                        newValue: change.newValue
                    )
                )
            }
        }
        try context.save()
        return revisions
    }

    // MARK: - Verwijderen

    /// Verwijdert een rit. In een regio met bewaarplicht wordt de rit een
    /// tombstone: hij verdwijnt uit lijsten en rapporten, maar blijft met zijn
    /// revisies bestaan. Zonder bewaarplicht wordt hij echt verwijderd,
    /// precies zoals voorheen.
    func delete(_ trip: Trip) throws {
        guard ruleSet.requiresAuditTrail else {
            context.delete(trip)
            try context.save()
            return
        }
        guard !trip.isDeleted else { return }

        trip.deletedAt = now()
        appendRevision(
            tripID: trip.id,
            tripStartDate: trip.startDate,
            kind: .deleted,
            field: nil,
            previousValue: "",
            newValue: ""
        )
        try context.save()
    }

    /// Zet een verwijderde rit terug. Ook dit is een vastgelegde wijziging.
    func restore(_ trip: Trip) throws {
        guard trip.isDeleted else { return }
        trip.deletedAt = nil
        if ruleSet.requiresAuditTrail {
            appendRevision(
                tripID: trip.id,
                tripStartDate: trip.startDate,
                kind: .restored,
                field: nil,
                previousValue: "",
                newValue: ""
            )
        }
        try context.save()
    }

    // MARK: - Revisies lezen

    /// Alle revisies van een rit, oudste eerst.
    func revisions(for tripID: UUID) throws -> [TripRevision] {
        let predicate = #Predicate<TripRevision> { $0.tripID == tripID }
        var descriptor = FetchDescriptor<TripRevision>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.changedAt)]
        return try context.fetch(descriptor)
    }

    // MARK: - Intern

    @discardableResult
    private func appendRevision(
        tripID: UUID,
        tripStartDate: Date,
        kind: TripChangeKind,
        field: TripAuditField?,
        previousValue: String,
        newValue: String
    ) -> TripRevision {
        let timestamp = now()
        let revision = TripRevision(
            tripID: tripID,
            changedAt: timestamp,
            tripStartDate: tripStartDate,
            changeKind: kind,
            field: field,
            previousValue: previousValue,
            newValue: newValue,
            wasContemporaneous: isContemporaneous(changedAt: timestamp, tripStartDate: tripStartDate)
        )
        context.insert(revision)
        return revision
    }

    /// Valt de wijziging binnen het venster waarin de regio een vastlegging
    /// nog als tijdig beschouwt? Zonder venster telt alles als tijdig.
    private func isContemporaneous(changedAt: Date, tripStartDate: Date) -> Bool {
        guard let window = ruleSet.contemporaneousWindow else { return true }
        return changedAt.timeIntervalSince(tripStartDate) <= window
    }
}

/// Momentopname van de fiscaal relevante velden van een rit, om vóór en ná een
/// wijziging te vergelijken.
///
/// Bewust een aparte, volledige lijst: als er een veld aan `Trip` wordt
/// toegevoegd dat hier niet in staat, wordt een wijziging daarvan niet
/// vastgelegd. `TripAuditField.allCases` en deze opsomming horen bij elkaar —
/// de harness bewaakt dat ze gelijk lopen.
private struct TripSnapshot {
    var isFinalised: Bool
    var values: [TripAuditField: String]

    init(_ trip: Trip) {
        isFinalised = trip.isFinalised
        values = [
            .startDate: Self.string(trip.startDate),
            .endDate: trip.endDate.map(Self.string) ?? "",
            .startAddress: trip.startAddress,
            .endAddress: trip.endAddress,
            .distanceKm: Self.string(trip.distanceKm),
            .startOdometer: trip.startOdometer.map(Self.string) ?? "",
            .endOdometer: trip.endOdometer.map(Self.string) ?? "",
            .category: trip.category.rawValue,
            .note: trip.note,
            .clientLabel: trip.clientLabel,
            .vehicle: trip.vehicle?.id.uuidString ?? "",
            .destinationPlace: trip.destinationPlace,
            .destinationStreet: trip.destinationStreet,
            .purpose: trip.purpose,
            .businessPartner: trip.businessPartner,
            .detourNote: trip.detourNote,
        ]
    }

    struct Change {
        var field: TripAuditField
        var previousValue: String
        var newValue: String
    }

    func changes(to other: TripSnapshot) -> [Change] {
        TripAuditField.allCases.compactMap { field in
            let previous = values[field] ?? ""
            let new = other.values[field] ?? ""
            guard previous != new else { return nil }
            return Change(field: field, previousValue: previous, newValue: new)
        }
    }

    /// Vaste, taalonafhankelijke weergave: revisies worden opgeslagen en
    /// mogen niet van de locale van het toestel afhangen.
    private static func string(_ value: Date) -> String {
        value.formatted(.iso8601)
    }

    private static func string(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}
