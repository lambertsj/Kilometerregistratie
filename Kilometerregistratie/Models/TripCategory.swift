import Foundation

/// De drie fiscale ritcategorieën die de Belastingdienst onderscheidt.
enum TripCategory: String, Codable, CaseIterable, Identifiable {
    case business = "zakelijk"
    case commute = "woon-werk"
    case personal = "privé"

    var id: String { rawValue }

    /// Schermnaam van de categorie. Dit is UI-taal en volgt de instelling van
    /// de gebruiker, in tegenstelling tot `RegionRuleSet.exportLabel(for:)`
    /// dat vaste, regiogebonden exportterminologie levert (bv. het Duitse
    /// "Geschäftsfahrt" voor een export, ongeacht de UI-taal).
    var displayName: String {
        switch self {
        case .business: String(localized: "Zakelijk", comment: "Ritcategorie: zakelijke rit")
        case .commute: String(localized: "Woon-werk", comment: "Ritcategorie: woon-werkrit")
        case .personal: String(localized: "Privé", comment: "Ritcategorie: privérit")
        }
    }
}
