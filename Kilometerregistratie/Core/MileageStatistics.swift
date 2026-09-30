import Foundation

/// Lichtgewicht waarde-representatie van een rit voor statistiekberekeningen.
/// Bewust losgekoppeld van het SwiftData-model zodat deze logica puur en
/// zonder database testbaar is.
struct TripSummary: Equatable {
    var startDate: Date
    var distanceKm: Double
    var category: TripCategory

    init(startDate: Date, distanceKm: Double, category: TripCategory) {
        self.startDate = startDate
        self.distanceKm = distanceKm
        self.category = category
    }
}

/// Kernstatistieken voor dashboard en rapportage: totalen per categorie,
/// de fiscale 500 km-privégrens voor leaserijders en de kilometervergoeding.
enum MileageStatistics {
    /// Fiscale grens: minder dan 500 privékilometer per kalenderjaar betekent
    /// geen bijtelling voor leaserijders.
    ///
    /// Dit is een *Nederlands* begrip; de grens hoort daarom bij de regelset
    /// (`RegionRuleSet.privateKmYearLimit`). De constante blijft hier staan als
    /// de waarde die `NetherlandsRuleSet` teruggeeft — lees hem in nieuwe code
    /// via de regelset, niet rechtstreeks.
    static let privateKmYearLimit = 500.0

    /// Waarschuwingsdrempel (fractie van de grens) voor de privé-teller.
    static let privateKmWarningFraction = 0.8

    static func totalKm(_ trips: [TripSummary], category: TripCategory? = nil) -> Double {
        trips
            .filter { category == nil || $0.category == category }
            .reduce(0) { $0 + $1.distanceKm }
    }

    /// Verdeling van kilometers over de drie categorieën (voor het taartdiagram).
    static func breakdown(_ trips: [TripSummary]) -> [TripCategory: Double] {
        var result: [TripCategory: Double] = [:]
        for trip in trips {
            result[trip.category, default: 0] += trip.distanceKm
        }
        return result
    }

    /// Privékilometers binnen één kalenderjaar (de 500 km-teller).
    static func privateKm(in year: Int, trips: [TripSummary], calendar: Calendar = .current) -> Double {
        trips
            .filter { $0.category == .personal && calendar.component(.year, from: $0.startDate) == year }
            .reduce(0) { $0 + $1.distanceKm }
    }

    enum PrivateKmStatus: Equatable {
        case ok
        case nearingLimit
        case overLimit
    }

    static func privateKmStatus(forYearTotal km: Double) -> PrivateKmStatus {
        privateKmStatus(forYearTotal: km, limit: privateKmYearLimit)
    }

    /// Status ten opzichte van de grens van een specifieke regio. Regio's
    /// zonder privékilometergrens (zoals Duitsland) hebben geen status: daar
    /// hoort de teller niet getoond te worden.
    static func privateKmStatus(forYearTotal km: Double, limit: Double?) -> PrivateKmStatus {
        guard let limit else { return .ok }
        if km >= limit { return .overLimit }
        if km >= limit * privateKmWarningFraction { return .nearingLimit }
        return .ok
    }

    /// Kilometervergoeding over zakelijke kilometers (tarief instelbaar,
    /// NL-norm €0,23/km).
    static func reimbursement(businessKm: Double, ratePerKm: Double) -> Double {
        businessKm * ratePerKm
    }
}
