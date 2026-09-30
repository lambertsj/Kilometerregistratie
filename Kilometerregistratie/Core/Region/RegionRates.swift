import Foundation

// ═══════════════════════════════════════════════════════════════════════════
//  ⚠️  DIT IS HET ENIGE BESTAND MET FISCALE BEDRAGEN.
//
//  Elk bedrag hieronder is gemarkeerd met `// VERIFY:` en moet vóór een
//  release gecontroleerd worden tegen de actuele wetgeving. Een nieuw
//  belastingjaar toevoegen is een *data*-wijziging in `RateTable`: er hoeft
//  geen code aangepast te worden.
//
//  Zet nooit een bedrag elders in de app neer — niet in een view, niet in een
//  string, niet als default van een model.
// ═══════════════════════════════════════════════════════════════════════════

/// Hoe een regio woon-werkkilometers fiscaal behandelt. Dit is géén tarief
/// maar een *rekenmodel*: Nederland en Duitsland verschillen hier structureel,
/// niet alleen in het bedrag.
enum CommuteTreatment: Equatable, Sendable {
    /// Woon-werkkilometers leveren in het rapport geen apart bedrag op; ze
    /// worden alleen als kilometers geteld. (Huidig Nederlands gedrag.)
    case kilometresOnly

    /// De regio rekent met een afstandsforfait dat de app bewust *niet*
    /// berekent, omdat het niet uit een rittenregistratie volgt.
    ///
    /// Duitsland: de Entfernungspauschale gaat per *enkele reis*-
    /// Entfernungskilometer per gewerkte dag — niet per gereden kilometer, en
    /// hij verdubbelt niet voor de terugweg. Dat is een berekening voor de
    /// aangifte, niet een veld in een Fahrtenbuch. Het rapport toont daarom
    /// alleen de kilometers.
    case distanceAllowanceOutsideScope
}

/// De tarieven van één regio voor één belastingjaar.
struct RegionRates: Equatable, Sendable {
    let taxYear: Int
    /// Vergoeding per *gereden* kilometer voor zakelijke ritten.
    let businessRatePerKm: Double
    let commuteTreatment: CommuteTreatment
    let currencyCode: String
}

/// Jaargesleutelde tarieventabel. `rates(for:)` kiest het meest recente jaar
/// dat niet ná het gevraagde jaar ligt, zodat een toekomstig jaar zonder
/// eigen regel automatisch het laatst bekende tarief gebruikt in plaats van
/// te crashen of naar nul te vallen.
struct RateTable: Sendable {
    let entriesByYear: [Int: RegionRates]

    func rates(for taxYear: Int) -> RegionRates {
        if let exact = entriesByYear[taxYear] { return exact }
        let applicableYears = entriesByYear.keys.filter { $0 <= taxYear }
        if let mostRecent = applicableYears.max(), let rates = entriesByYear[mostRecent] {
            return rates
        }
        // Het gevraagde jaar ligt vóór elk bekend jaar: neem het oudste.
        guard let earliest = entriesByYear.keys.min(), let rates = entriesByYear[earliest] else {
            preconditionFailure("RateTable mag niet leeg zijn")
        }
        return rates
    }
}

enum TaxRates {
    // MARK: - Nederland

    /// LET OP: `0.23` is óók de default van `AppSettings.reimbursementRatePerKm`
    /// en is voor bestaande gebruikers een opgeslagen, zelf instelbare waarde.
    /// Deze tabel levert alleen de *voorgestelde* waarde; wijzig de default van
    /// het model niet zonder migratie, anders verandert bestaand NL-gedrag.
    static let netherlands = RateTable(entriesByYear: [
        // VERIFY: onbelaste reiskostenvergoeding NL 2024 — € 0,23 per km.
        2024: RegionRates(taxYear: 2024, businessRatePerKm: 0.23, commuteTreatment: .kilometresOnly, currencyCode: "EUR"),
        // VERIFY: onbelaste reiskostenvergoeding NL 2025 — € 0,23 per km.
        2025: RegionRates(taxYear: 2025, businessRatePerKm: 0.23, commuteTreatment: .kilometresOnly, currencyCode: "EUR"),
        // VERIFY: onbelaste reiskostenvergoeding NL 2026 — bedrag nog te
        // controleren; staat nu bewust gelijk aan 2025 zodat het gedrag van
        // bestaande gebruikers niet stilletjes verandert.
        2026: RegionRates(taxYear: 2026, businessRatePerKm: 0.23, commuteTreatment: .kilometresOnly, currencyCode: "EUR"),
    ])

    // MARK: - Duitsland

    static let germany = RateTable(entriesByYear: [
        // VERIFY: Kilometerpauschale Dienstreise met eigen auto (DE) —
        // € 0,30 per *gereden* km. Losstaand van de Entfernungspauschale
        // hieronder, die de app niet berekent (zie `CommuteTreatment`).
        2024: RegionRates(taxYear: 2024, businessRatePerKm: 0.30, commuteTreatment: .distanceAllowanceOutsideScope, currencyCode: "EUR"),
        // VERIFY: idem 2025.
        2025: RegionRates(taxYear: 2025, businessRatePerKm: 0.30, commuteTreatment: .distanceAllowanceOutsideScope, currencyCode: "EUR"),
        // VERIFY: idem 2026.
        2026: RegionRates(taxYear: 2026, businessRatePerKm: 0.30, commuteTreatment: .distanceAllowanceOutsideScope, currencyCode: "EUR"),
    ])

    // MARK: - Bewaartermijn en "zeitnah"-venster

    /// VERIFY: bewaartermijn Duitsland. Tien jaar volgt uit § 147 Abs. 3 AO
    /// voor Buchführungsunterlagen; voor een Fahrtenbuch van een werknemer
    /// (§ 8 Abs. 2 Satz 4 EStG) is die grondslag zwakker. De app gebruikt dit
    /// getal niet om iets te verwijderen — het beleid is "nooit hard
    /// verwijderen" — en noemt het niet in gebruikerstekst.
    static let germanRetentionYears = 10

    /// VERIFY: het "zeitnah"-venster. Er is geen wettelijke harde grens; zeven
    /// dagen na het einde van de rit is een verdedigbare, veilige aanname.
    /// Wijzigingen ná dit venster worden in de audit trail als zodanig
    /// gemarkeerd (niet geblokkeerd) — zie fase 2.
    static let germanContemporaneousWindow: TimeInterval = 7 * 24 * 60 * 60
}
