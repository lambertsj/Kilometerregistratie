import Foundation
import SwiftData

/// Eén geregistreerde rit. Bevat alles wat een Belastingdienst-conforme
/// rittenadministratie per rit nodig heeft: datum, begin-/eindadres,
/// afstand, kilometerstanden, categorie en doel.
@Model
final class Trip {
    var id: UUID
    var startDate: Date
    var endDate: Date?

    var startAddress: String
    var endAddress: String
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?

    /// Afstand in kilometers.
    var distanceKm: Double

    /// Kilometerstand bij vertrek/aankomst (optioneel, handmatig in te vullen).
    var startOdometer: Double?
    var endOdometer: Double?

    /// Opslag als raw value zodat SwiftData er efficiënt op kan filteren.
    var categoryRawValue: String

    /// Doel/notitie van de rit (fiscaal veld) en optioneel klant/project-label.
    var note: String
    var clientLabel: String

    /// True als de rit door automatische GPS-detectie is vastgelegd.
    var isAutomaticallyRecorded: Bool

    /// Gecodeerde [RoutePoint]-blob; nil voor handmatig ingevoerde ritten.
    var routeData: Data?

    var vehicle: Vehicle?

    // MARK: - Duitse Fahrtenbuch-velden
    //
    // Deze velden zijn *regioafhankelijk* verplicht (zie
    // `RegionRuleSet.requiredFields(for:)`) en nooit globaal: de Nederlandse
    // flow krijgt er geen verplichte velden bij. Ze hebben een lege
    // standaardwaarde zodat bestaande ritten ongewijzigd blijven.

    /// Reiseziel: plaats van bestemming.
    var destinationPlace: String = ""
    /// Reiseziel: straat van bestemming.
    var destinationStreet: String = ""
    /// Reisezweck: het doel van de rit.
    var purpose: String = ""
    /// Aufgesuchter Geschäftspartner: de bezochte klant of relatie.
    var businessPartner: String = ""
    /// Umweg: toelichting bij een omweg, als die er was.
    var detourNote: String = ""

    /// Tombstone. Een regio met bewaarplicht (Duitsland) verwijdert een rit
    /// niet echt maar markeert hem hier; de rit verdwijnt uit alle lijsten en
    /// rapporten, maar blijft met zijn revisies bewaard. `nil` betekent
    /// "niet verwijderd". Nederland verwijdert nog gewoon hard, dus daar komt
    /// deze waarde nooit voor.
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    /// Een rit telt als vastgelegd zodra hij een eindtijd heeft. Wijzigingen
    /// vóór dat moment horen bij het opbouwen van de registratie (de
    /// GPS-opname loopt nog) en leveren geen revisie op; wijzigingen daarna
    /// wel.
    var isFinalised: Bool { endDate != nil }

    var category: TripCategory {
        get { TripCategory(rawValue: categoryRawValue) ?? .business }
        set { categoryRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        startAddress: String = "",
        endAddress: String = "",
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        distanceKm: Double = 0,
        startOdometer: Double? = nil,
        endOdometer: Double? = nil,
        category: TripCategory = .business,
        note: String = "",
        clientLabel: String = "",
        isAutomaticallyRecorded: Bool = false,
        routeData: Data? = nil,
        vehicle: Vehicle? = nil,
        destinationPlace: String = "",
        destinationStreet: String = "",
        purpose: String = "",
        businessPartner: String = "",
        detourNote: String = "",
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.distanceKm = distanceKm
        self.startOdometer = startOdometer
        self.endOdometer = endOdometer
        self.categoryRawValue = category.rawValue
        self.note = note
        self.clientLabel = clientLabel
        self.isAutomaticallyRecorded = isAutomaticallyRecorded
        self.routeData = routeData
        self.vehicle = vehicle
        self.destinationPlace = destinationPlace
        self.destinationStreet = destinationStreet
        self.purpose = purpose
        self.businessPartner = businessPartner
        self.detourNote = detourNote
        self.deletedAt = deletedAt
    }
}
