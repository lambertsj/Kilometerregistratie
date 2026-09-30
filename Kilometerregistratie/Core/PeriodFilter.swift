import Foundation

/// Gedeelde periodekeuze voor ritlijst, dashboard en rapportage.
///
/// De `rawValue` is bewust een stabiele, taalonafhankelijke sleutel. Hij was
/// eerder Nederlandse UI-tekst ("Deze maand"), waardoor dezelfde string
/// tegelijk identiteit, schermtekst én rapporttekst was. Voor de UI is er nu
/// `displayName` (zie `PeriodFilter+UI`) en voor exports `exportLabel(for:)`,
/// dat de taal van de fiscale regio volgt.
enum PeriodFilter: String, CaseIterable, Identifiable {
    case all
    case month
    case quarter
    case year

    var id: String { rawValue }

    /// Begin van de gekozen periode; nil betekent geen ondergrens.
    func startDate(relativeTo now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .all:
            return nil
        case .month:
            return calendar.dateInterval(of: .month, for: now)?.start
        case .quarter:
            return calendar.dateInterval(of: .quarter, for: now)?.start
        case .year:
            return calendar.dateInterval(of: .year, for: now)?.start
        }
    }

    /// Periodeaanduiding zoals die in een exportbestand komt. Volgt de regio,
    /// niet de UI-taal: een Fahrtenbuch voor het Finanzamt is Duitstalig, ook
    /// als de app in het Nederlands staat.
    func exportLabel(for region: TaxRegion) -> String {
        switch region {
        case .netherlands:
            switch self {
            case .all: "Alles"
            case .month: "Deze maand"
            case .quarter: "Dit kwartaal"
            case .year: "Dit jaar"
            }
        case .germany:
            switch self {
            case .all: "Gesamter Zeitraum"
            case .month: "Laufender Monat"
            case .quarter: "Laufendes Quartal"
            case .year: "Laufendes Jahr"
            }
        }
    }
}
