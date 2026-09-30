import SwiftUI

extension PeriodFilter {
    /// Schermtekst voor de periodekiezer. Staat los van `exportLabel(for:)`:
    /// de UI volgt de taal van de gebruiker, een export de taal van de
    /// fiscale regio.
    var displayName: String {
        switch self {
        case .all: String(localized: "Alles", comment: "Periodefilter: alle ritten")
        case .month: String(localized: "Deze maand", comment: "Periodefilter: deze maand")
        case .quarter: String(localized: "Dit kwartaal", comment: "Periodefilter: dit kwartaal")
        case .year: String(localized: "Dit jaar", comment: "Periodefilter: dit jaar")
        }
    }
}
