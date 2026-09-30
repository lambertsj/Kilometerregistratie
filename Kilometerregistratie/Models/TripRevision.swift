import Foundation
import SwiftData

/// Eén vastgelegde wijziging aan een rit. Append-only: revisies worden nooit
/// gewijzigd en nooit verwijderd — dat is precies waar hun bewijswaarde in zit
/// (§ 8 Abs. 2 Satz 4 EStG jo. R 8.1 Abs. 9 Nr. 2 LStR: een elektronisch
/// Fahrtenbuch heeft alleen waarde als latere wijzigingen zichtbaar blijven).
///
/// De koppeling naar de rit is bewust een losse `tripID` en géén SwiftData-
/// relatie: revisies moeten een verwijderde rit overleven, en een relatie met
/// een delete rule zou ze kunnen meenemen.
@Model
final class TripRevision {
    var id: UUID
    var tripID: UUID
    /// Wanneer de wijziging is doorgevoerd.
    var changedAt: Date
    /// Vertrektijd van de rit waar het om gaat; nodig om te bepalen of de
    /// wijziging binnen het "zeitnah"-venster viel.
    var tripStartDate: Date

    var changeKindRawValue: String
    /// Sleutel uit `TripAuditField`; leeg bij aanmaken/verwijderen.
    var fieldRawValue: String
    var previousValue: String
    var newValue: String

    /// Viel de wijziging binnen het venster waarin de regio een registratie
    /// nog als tijdig beschouwt? Bij het aanmaken van de rit altijd true.
    var wasContemporaneous: Bool

    var changeKind: TripChangeKind {
        TripChangeKind(rawValue: changeKindRawValue) ?? .updated
    }

    var field: TripAuditField? {
        TripAuditField(rawValue: fieldRawValue)
    }

    init(
        id: UUID = UUID(),
        tripID: UUID,
        changedAt: Date,
        tripStartDate: Date,
        changeKind: TripChangeKind,
        field: TripAuditField?,
        previousValue: String,
        newValue: String,
        wasContemporaneous: Bool
    ) {
        self.id = id
        self.tripID = tripID
        self.changedAt = changedAt
        self.tripStartDate = tripStartDate
        self.changeKindRawValue = changeKind.rawValue
        self.fieldRawValue = field?.rawValue ?? ""
        self.previousValue = previousValue
        self.newValue = newValue
        self.wasContemporaneous = wasContemporaneous
    }
}
