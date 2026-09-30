import Foundation

/// Eén rij van het rittenrapport. De Nederlandse velden staan bovenaan; de
/// Duitse Fahrtenbuch-velden hebben een lege standaardwaarde, zodat bestaande
/// Nederlandse aanroepen en exports ongewijzigd blijven.
struct TripReportRow: Equatable {
    var startDate: Date
    var endDate: Date?
    var startAddress: String
    var endAddress: String
    var startOdometer: Double?
    var endOdometer: Double?
    var distanceKm: Double
    var category: TripCategory
    var note: String
    var clientLabel: String
    var vehicleName: String
    var vehicleLicensePlate: String = ""

    /// Duitse velden (R 8.1 Abs. 9 Nr. 2 LStR). Leeg voor Nederlandse ritten.
    var destinationPlace: String = ""
    var destinationStreet: String = ""
    var purpose: String = ""
    var businessPartner: String = ""
    var detourNote: String = ""
}

struct ReportSummary: Equatable {
    var tripCount: Int
    var totalKm: Double
    var businessKm: Double
    var commuteKm: Double
    var personalKm: Double
    var reimbursement: Double

    func km(for category: TripCategory) -> Double {
        switch category {
        case .business: businessKm
        case .commute: commuteKm
        case .personal: personalKm
        }
    }
}

/// Kilometerstand aan begin en eind van de gerapporteerde periode, zodat de
/// totalen aantoonbaar sluiten (Duitse eis: de reeks moet aansluiten).
struct OdometerRange: Equatable {
    var start: Double
    var end: Double

    var delta: Double { end - start }
}

/// Pure rapportgeneratie: rijen → kolomwaarden, CSV-tekst en totalen. PDF en
/// xlsx bouwen hierop voort en delen dezelfde `ExportLayout`, zodat de drie
/// formaten niet meer met de hand in sync gehouden hoeven te worden.
enum ReportGenerator {
    // MARK: - Totalen

    static func summary(rows: [TripReportRow], ratePerKm: Double) -> ReportSummary {
        let business = rows.filter { $0.category == .business }.reduce(0) { $0 + $1.distanceKm }
        let commute = rows.filter { $0.category == .commute }.reduce(0) { $0 + $1.distanceKm }
        let personal = rows.filter { $0.category == .personal }.reduce(0) { $0 + $1.distanceKm }
        return ReportSummary(
            tripCount: rows.count,
            totalKm: business + commute + personal,
            businessKm: business,
            commuteKm: commute,
            personalKm: personal,
            reimbursement: MileageStatistics.reimbursement(businessKm: business, ratePerKm: ratePerKm)
        )
    }

    // MARK: - Kolomwaarden

    /// De waarde van één kolom, als tekst zoals die in het rapport komt.
    /// Dit is de enige plek waar een `ExportField` op een rijveld wordt
    /// afgebeeld — CSV, xlsx en PDF gebruiken alle drie deze functie.
    static func value(
        for field: ExportField,
        row: TripReportRow,
        ruleSet: any RegionRuleSet
    ) -> String {
        let formatting = ruleSet.formatting
        switch field {
        case .date:
            return formatting.date(row.startDate)
        case .departureTime:
            return formatting.time(row.startDate)
        case .arrivalTime:
            return row.endDate.map { formatting.time($0) } ?? ""
        case .startAddress:
            return row.startAddress
        case .endAddress:
            return row.endAddress
        case .startOdometer:
            return row.startOdometer.map { formatting.number($0, decimals: field.decimals) } ?? ""
        case .endOdometer:
            return row.endOdometer.map { formatting.number($0, decimals: field.decimals) } ?? ""
        case .distanceKm:
            return formatting.number(row.distanceKm, decimals: field.decimals)
        case .category:
            return ruleSet.exportShortLabel(for: row.category)
        case .note:
            return row.note
        case .clientLabel:
            return row.clientLabel
        case .vehicleName:
            return row.vehicleName
        case .destinationPlace:
            return row.destinationPlace
        case .destinationStreet:
            return row.destinationStreet
        case .purpose:
            return row.purpose
        case .businessPartner:
            return row.businessPartner
        case .detourNote:
            return row.detourNote
        }
    }

    /// De numerieke waarde van een kolom, of `nil` als de kolom tekst is of
    /// leeg is. Gebruikt door de xlsx-builder om echte getalcellen te schrijven.
    static func numericValue(for field: ExportField, row: TripReportRow) -> Double? {
        switch field {
        case .startOdometer: row.startOdometer
        case .endOdometer: row.endOdometer
        case .distanceKm: row.distanceKm
        default: nil
        }
    }

    static func values(
        for row: TripReportRow,
        layout: ExportLayout,
        ruleSet: any RegionRuleSet
    ) -> [String] {
        layout.columns.map { value(for: $0.field, row: row, ruleSet: ruleSet) }
    }

    /// De samenvattingsregels als label/waarde-paren, klaar om te tekenen of
    /// te schrijven. Regels die gegevens missen (bv. kilometerstanden) vallen
    /// weg in plaats van als "0" te verschijnen.
    static func summaryLines(
        _ summary: ReportSummary,
        layout: ExportLayout,
        ruleSet: any RegionRuleSet,
        odometer: OdometerRange? = nil
    ) -> [(label: String, value: String)] {
        let formatting = ruleSet.formatting
        return layout.summaryLines.compactMap { line in
            switch line {
            case .tripCount(let label):
                return (label, formatting.number(Double(summary.tripCount), decimals: 0))
            case .totalKm(let label):
                return (label, formatting.distance(summary.totalKm))
            case .categoryKm(let category, let label):
                return (label, formatting.distance(summary.km(for: category)))
            case .reimbursement(let label):
                return (label, formatting.currency(summary.reimbursement))
            case .odometerRange(let label):
                guard let odometer else { return nil }
                return (
                    label,
                    formatting.number(odometer.start, decimals: 0)
                        + " – " + formatting.number(odometer.end, decimals: 0)
                )
            case .odometerDelta(let label):
                guard let odometer else { return nil }
                return (label, formatting.distance(odometer.delta))
            case .unrecordedKm(let label):
                guard let odometer else { return nil }
                return (label, formatting.distance(odometer.delta - summary.totalKm))
            }
        }
    }

    /// Samenvattingsregels voor het spreadsheet: label plus de *numerieke*
    /// waarde, zodat de xlsx echte getalcellen kan schrijven in plaats van
    /// opgemaakte tekst.
    static func spreadsheetSummaryRows(
        _ summary: ReportSummary,
        layout: ExportLayout,
        odometer: OdometerRange? = nil
    ) -> [(label: String, value: Double, decimals: Int)] {
        layout.spreadsheetSummaryLines.compactMap { line in
            switch line {
            case .tripCount(let label):
                return (label, Double(summary.tripCount), 0)
            case .totalKm(let label):
                return (label, summary.totalKm, 1)
            case .categoryKm(let category, let label):
                return (label, summary.km(for: category), 1)
            case .reimbursement(let label):
                return (label, summary.reimbursement, 2)
            case .odometerDelta(let label):
                guard let odometer else { return nil }
                return (label, odometer.delta, 1)
            case .unrecordedKm(let label):
                guard let odometer else { return nil }
                return (label, odometer.delta - summary.totalKm, 1)
            case .odometerRange:
                // Een bereik is geen enkel getal; dat staat alleen in de PDF.
                return nil
            }
        }
    }

    // MARK: - Kilometerstand over de periode

    /// De kilometerstand aan het begin en eind van de gerapporteerde periode.
    ///
    /// Levert `nil` als de reeks niet te bepalen is: bij ritten van meerdere
    /// voertuigen (een Fahrtenbuch wordt per voertuig gevoerd) of als de
    /// eerste of laatste stand ontbreekt. De samenvatting laat de
    /// kilometerstandregels dan weg in plaats van een misleidend getal te
    /// tonen.
    static func odometerRange(for rows: [TripReportRow]) -> OdometerRange? {
        guard !rows.isEmpty else { return nil }
        guard Set(rows.map(\.vehicleName)).count == 1 else { return nil }

        let ordered = rows.sorted { $0.startDate < $1.startDate }
        guard let start = ordered.first?.startOdometer,
              let end = ordered.last?.endOdometer else { return nil }
        return OdometerRange(start: start, end: end)
    }

    /// De namen van de voertuigen in deze selectie, zonder lege.
    static func vehicleNames(in rows: [TripReportRow]) -> [String] {
        Array(Set(rows.map(\.vehicleName).filter { !$0.isEmpty })).sorted()
    }

    // MARK: - CSV

    /// CSV met puntkomma-scheiding en decimale komma: dat is wat zowel de
    /// Nederlandse als de Duitse Excel-instellingen standaard verwachten.
    static func csv(rows: [TripReportRow], ruleSet: any RegionRuleSet) -> String {
        let layout = ruleSet.exportLayout
        let separator = ruleSet.formatting.csvSeparator
        var lines = [layout.headers.map { escapeCSVField($0, separator: separator) }.joined(separator: separator)]
        for row in rows {
            let fields = values(for: row, layout: layout, ruleSet: ruleSet)
            lines.append(fields.map { escapeCSVField($0, separator: separator) }.joined(separator: separator))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func escapeCSVField(_ field: String, separator: String) -> String {
        if field.contains(separator) || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
