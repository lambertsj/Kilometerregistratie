import Foundation

/// De velden van een rit die in de audit trail bijgehouden worden, met een
/// stabiele sleutel. De sleutels worden opgeslagen en mogen daarom nooit
/// hernoemd worden — voeg alleen toe.
///
/// Bewust breder dan `TripField`: `TripField` beschrijft wat een regio
/// *verplicht* stelt bij invoer, deze opsomming beschrijft wat er allemaal
/// gewijzigd kán worden en dus vastgelegd moet worden.
enum TripAuditField: String, CaseIterable, Codable, Sendable {
    case startDate
    case endDate
    case startAddress
    case endAddress
    case distanceKm
    case startOdometer
    case endOdometer
    case category
    case note
    case clientLabel
    case vehicle
    case destinationPlace
    case destinationStreet
    case purpose
    case businessPartner
    case detourNote

    /// Leesbare naam voor het wijzigingsoverzicht.
    var displayName: String {
        switch self {
        case .startDate: "Vertrektijd"
        case .endDate: "Aankomsttijd"
        case .startAddress: "Beginadres"
        case .endAddress: "Eindadres"
        case .distanceKm: "Afstand"
        case .startOdometer: "Kilometerstand begin"
        case .endOdometer: "Kilometerstand eind"
        case .category: "Categorie"
        case .note: "Doel/notitie"
        case .clientLabel: "Klant/project"
        case .vehicle: "Voertuig"
        case .destinationPlace: "Bestemming (plaats)"
        case .destinationStreet: "Bestemming (straat)"
        case .purpose: "Reisdoel"
        case .businessPartner: "Zakenrelatie"
        case .detourNote: "Omweg"
        }
    }
}

/// Wat er met de rit gebeurde.
enum TripChangeKind: String, Codable, Sendable {
    case created
    case updated
    /// Verwijderd in een regio met bewaarplicht: de rit blijft als tombstone
    /// bestaan.
    case deleted
    /// Een eerder verwijderde rit is teruggezet.
    case restored
}
