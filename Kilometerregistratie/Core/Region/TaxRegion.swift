import Foundation

/// De fiscale regio waarvan de regels gelden. Bewust los van taal en van
/// `Locale`: een Nederlandstalige gebruiker in Duitsland moet de Duitse
/// regels kunnen draaien en omgekeerd. Domeinlogica kijkt daarom *nooit*
/// naar `Locale` of de UI-taal, alleen naar deze waarde.
enum TaxRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case netherlands = "nl"
    case germany = "de"

    var id: String { rawValue }

    /// De regelset die bij deze regio hoort. Alle regiospecifieke logica
    /// hangt hierachter; er staat nergens anders in de app een
    /// `if region == .germany`.
    var ruleSet: any RegionRuleSet {
        switch self {
        case .netherlands: NetherlandsRuleSet()
        case .germany: GermanyRuleSet()
        }
    }

    /// Voorstel voor een nieuwe installatie, afgeleid van de regio-instelling
    /// van het toestel. Dit is de *enige* plek waar `Locale` een rol speelt,
    /// en de gebruiker kan het altijd overschrijven (onboarding + Instellingen).
    /// Onbekende regio's vallen terug op Nederland: dat houdt het gedrag voor
    /// bestaande gebruikers ongewijzigd.
    static func suggested(for regionCode: String?) -> TaxRegion {
        switch regionCode?.uppercased() {
        case "DE": .germany
        default: .netherlands
        }
    }
}
