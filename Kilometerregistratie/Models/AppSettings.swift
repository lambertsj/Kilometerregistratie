import Foundation
import SwiftData

/// Hoe ritten geregistreerd worden.
enum TrackingMode: String, Codable, CaseIterable, Identifiable {
    case automatic = "automatisch"
    case manual = "handmatig"
    case hybrid = "hybride"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: String(localized: "Automatisch", comment: "Registratiemodus: automatisch")
        case .manual: String(localized: "Handmatig", comment: "Registratiemodus: handmatig")
        case .hybrid: String(localized: "Hybride", comment: "Registratiemodus: hybride")
        }
    }
}

/// Afweging tussen GPS-nauwkeurigheid en batterijverbruik tijdens een
/// opname. De daadwerkelijke `CLLocationAccuracy`/`distanceFilter`-waarden
/// staan in `LocationTrackingService` (dat CoreLocation importeert); dit
/// model blijft er bewust los van.
enum LocationAccuracyPreference: String, Codable, CaseIterable, Identifiable {
    case batterySaver = "batterijbesparend"
    case balanced = "gebalanceerd"
    case precise = "nauwkeurig"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .batterySaver: String(localized: "Batterijbesparend", comment: "GPS-nauwkeurigheid: batterijbesparend")
        case .balanced: String(localized: "Gebalanceerd", comment: "GPS-nauwkeurigheid: gebalanceerd")
        case .precise: String(localized: "Nauwkeurig", comment: "GPS-nauwkeurigheid: nauwkeurig")
        }
    }

    var detailText: String {
        switch self {
        case .batterySaver:
            String(localized: "Minder frequente GPS-updates: langere accuduur, iets minder nauwkeurige route en afstand.", comment: "Toelichting bij batterijbesparende GPS-nauwkeurigheid")
        case .balanced:
            String(localized: "Standaard: goede afstandsnauwkeurigheid bij normaal batterijgebruik.", comment: "Toelichting bij gebalanceerde GPS-nauwkeurigheid")
        case .precise:
            String(localized: "Vaakst GPS-updates voor de nauwkeurigste route en afstand; kost meer batterij.", comment: "Toelichting bij nauwkeurige GPS-nauwkeurigheid")
        }
    }
}

/// App-instellingen als singleton-record in SwiftData (er bestaat er altijd
/// precies één; `AppSettings.fetchOrCreate` bewaakt dat).
@Model
final class AppSettings {
    var trackingModeRawValue: String

    /// Kilometervergoeding in euro per km (NL-norm 2024/2025: €0,23).
    var reimbursementRatePerKm: Double

    /// Ritten die binnen deze werktijden starten worden standaard als
    /// zakelijk voorgesteld (kantooruren-regel). Minuten sinds middernacht.
    var workHoursEnabled: Bool
    var workDayStartMinute: Int
    var workDayEndMinute: Int
    /// Weekdagen waarop de kantooruren-regel geldt (1 = zondag … 7 = zaterdag,
    /// conform Calendar.weekday). Opgeslagen als comma-separated string.
    var workWeekdaysRawValue: String

    /// Automatische stop-detectie: minuten stilstand voordat een rit eindigt.
    var autoStopThresholdMinutes: Int

    /// Versleutelde iCloud-back-up; staat bewust standaard UIT (privacy-first).
    var iCloudBackupEnabled: Bool

    /// Afweging nauwkeurigheid ↔ batterij tijdens een opname. Standaardwaarde
    /// inline zodat bestaande installaties dit veld automatisch als
    /// "gebalanceerd" krijgen bij een lightweight migration.
    var locationAccuracyRawValue: String = LocationAccuracyPreference.balanced.rawValue

    /// De fiscale regio waarvan de regels gelden. Bewust hier en niet op
    /// `Vehicle`: `Trip.vehicle` is optioneel, dus een voertuiggebonden regio
    /// zou ongedefinieerd zijn voor handmatige ritten zonder voertuig — en het
    /// invoerformulier zou dan niet weten welke velden het moet vragen.
    ///
    /// De inline default houdt bestaande installaties op Nederland, zodat een
    /// lightweight migration het veld vanzelf goed invult en er voor huidige
    /// gebruikers niets verandert.
    var taxRegionRawValue: String = TaxRegion.netherlands.rawValue

    var taxRegion: TaxRegion {
        get { TaxRegion(rawValue: taxRegionRawValue) ?? .netherlands }
        set { taxRegionRawValue = newValue.rawValue }
    }

    /// De regelset die bij de ingestelde regio hoort. Alle regioafhankelijke
    /// beslissingen lopen hierlangs.
    var ruleSet: any RegionRuleSet { taxRegion.ruleSet }

    var trackingMode: TrackingMode {
        get { TrackingMode(rawValue: trackingModeRawValue) ?? .manual }
        set { trackingModeRawValue = newValue.rawValue }
    }

    var locationAccuracyPreference: LocationAccuracyPreference {
        get { LocationAccuracyPreference(rawValue: locationAccuracyRawValue) ?? .balanced }
        set { locationAccuracyRawValue = newValue.rawValue }
    }

    var workWeekdays: Set<Int> {
        get { Set(workWeekdaysRawValue.split(separator: ",").compactMap { Int($0) }) }
        set { workWeekdaysRawValue = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    init(
        trackingMode: TrackingMode = .manual,
        reimbursementRatePerKm: Double = 0.23,
        workHoursEnabled: Bool = false,
        workDayStartMinute: Int = 9 * 60,
        workDayEndMinute: Int = 17 * 60,
        workWeekdays: Set<Int> = [2, 3, 4, 5, 6], // ma t/m vr
        autoStopThresholdMinutes: Int = 3,
        iCloudBackupEnabled: Bool = false,
        locationAccuracyPreference: LocationAccuracyPreference = .balanced,
        taxRegion: TaxRegion = .netherlands
    ) {
        self.trackingModeRawValue = trackingMode.rawValue
        self.reimbursementRatePerKm = reimbursementRatePerKm
        self.workHoursEnabled = workHoursEnabled
        self.workDayStartMinute = workDayStartMinute
        self.workDayEndMinute = workDayEndMinute
        self.workWeekdaysRawValue = workWeekdays.sorted().map(String.init).joined(separator: ",")
        self.autoStopThresholdMinutes = autoStopThresholdMinutes
        self.iCloudBackupEnabled = iCloudBackupEnabled
        self.locationAccuracyRawValue = locationAccuracyPreference.rawValue
        self.taxRegionRawValue = taxRegion.rawValue
    }

    /// Haalt het enige settings-record op, of maakt het aan als het nog niet bestaat.
    static func fetchOrCreate(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
