import Foundation

/// Eén kolomwaarde van het rapport. Bestond eerder impliciet als positie in
/// drie losse lijsten (`ReportGenerator.columnHeaders`, de CSV-velden en
/// `PDFReportRenderer.columns`); nu is de betekenis expliciet, zodat CSV,
/// xlsx en PDF niet meer met de hand in sync gehouden hoeven te worden.
enum ExportField: String, Equatable, Sendable {
    case date
    case departureTime
    case arrivalTime
    case startAddress
    case endAddress
    case startOdometer
    case endOdometer
    case distanceKm
    case category
    case note
    case clientLabel
    case vehicleName

    /// Duitse Fahrtenbuch-kolommen.
    case destinationPlace
    case destinationStreet
    case purpose
    case businessPartner
    case detourNote

    /// True voor kolommen die in een spreadsheet een getal moeten zijn in
    /// plaats van tekst (xlsx schrijft die als `<v>`-cel).
    var isNumeric: Bool {
        switch self {
        case .startOdometer, .endOdometer, .distanceKm:
            true
        case .date, .departureTime, .arrivalTime, .startAddress, .endAddress,
             .category, .note, .clientLabel, .vehicleName,
             .destinationPlace, .destinationStreet, .purpose, .businessPartner, .detourNote:
            false
        }
    }

    /// Aantal decimalen waarmee een numerieke kolom geschreven wordt.
    var decimals: Int {
        switch self {
        case .startOdometer, .endOdometer: 0
        case .distanceKm: 1
        default: 0
        }
    }
}

struct ExportColumn: Equatable, Sendable {
    let field: ExportField
    let header: String
    /// Kolombreedte in punten voor de PDF-tabel (A4 liggend, 769,8 pt bruikbaar).
    let pdfWidth: Double

    init(_ field: ExportField, header: String, pdfWidth: Double) {
        self.field = field
        self.header = header
        self.pdfWidth = pdfWidth
    }
}

/// Eén regel in het samenvattingsblok.
enum SummaryLine: Equatable, Sendable {
    case tripCount(label: String)
    case totalKm(label: String)
    case categoryKm(TripCategory, label: String)
    case reimbursement(label: String)
    /// Kilometerstand aan begin/eind van de periode en het verschil daartussen,
    /// zodat de totalen aantoonbaar sluiten.
    case odometerRange(label: String)
    case odometerDelta(label: String)
    /// Het verschil tussen wat de kilometerteller over de periode aangeeft en
    /// wat de geregistreerde ritten samen optellen. Nul betekent dat de
    /// registratie sluit.
    case unrecordedKm(label: String)
}

/// Volledige beschrijving van hoe een rapport van één regio eruitziet.
/// Bevat geen opmaaklogica en geen tekenwerk: alleen wat er in staat.
struct ExportLayout: Equatable, Sendable {
    let documentTitle: String
    let periodLabelPrefix: String
    let generatedAtLabel: String
    let columns: [ExportColumn]
    let summaryTitle: String
    /// Samenvattingsregels voor de PDF (opgemaakte tekst).
    let summaryLines: [SummaryLine]
    /// Samenvattingsregels voor het spreadsheet. Bewust een aparte lijst: de
    /// xlsx-export gebruikt al sinds versie 1 andere, langere labels dan de
    /// PDF ("Totaal km" versus "Totaal") en schrijft de waarden als echte
    /// getalcellen. Die uitvoer moet byte-identiek blijven.
    let spreadsheetSummaryLines: [SummaryLine]
    /// Tabbladnaam in de xlsx.
    let spreadsheetSheetName: String
    /// Verbinding tussen begin- en einddatum bij een aangepaste periode
    /// ("1-1-2026 t/m 31-3-2026").
    let customRangeSeparator: String

    /// Aanduiding van het voertuig in de kop van het rapport, bv. "Fahrzeug".
    /// `nil` als de regio het voertuig niet in de kop zet — het Nederlandse
    /// rapport doet dat niet en moet ongewijzigd blijven.
    let vehicleHeaderPrefix: String?
    /// Tekst bij een selectie die meerdere voertuigen omvat; dan is een
    /// sluitende kilometerreeks per definitie niet aan te tonen.
    let multipleVehiclesNote: String?
    /// Zet het samenvattingsblok altijd op een eigen pagina, ook als het nog
    /// onder de tabel zou passen.
    let summaryAlwaysOnOwnPage: Bool
    /// Kop boven de legenda met de volledige categorienamen; `nil` als de
    /// regio geen afgekorte namen in de tabel gebruikt.
    let legendTitle: String?
    /// Basisnaam van het exportbestand, zonder datum en extensie.
    let fileNameStem: String

    var headers: [String] { columns.map(\.header) }

    var totalPdfWidth: Double { columns.reduce(0) { $0 + $1.pdfWidth } }
}
