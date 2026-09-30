import Foundation

/// Geometrie van de rapportpagina, in PDF-punten (A4 liggend). Staat hier en
/// niet in de renderer, zodat de paginaverdeling pure, testbare logica is:
/// `PDFReportRenderer` tekent alleen nog wat het plan zegt.
struct ReportPageGeometry: Equatable, Sendable {
    var pageWidth: Double = 841.8
    var pageHeight: Double = 595.2
    var margin: Double = 36
    var rowHeight: Double = 22
    /// Verticale ruimte tussen de paginatitel en de tabelkop.
    var headerBlockHeight: Double = 44
    /// Hoogte van één extra kopregel (bv. de voertuigregel).
    var headerLineHeight: Double = 13
    /// Marge onderaan waar geen rij meer begonnen wordt.
    var bottomSlack: Double = 8
    /// Hoogte die het samenvattingsblok nodig heeft.
    var summaryBlockHeight: Double = 120

    static let a4Landscape = ReportPageGeometry()

    /// Dezelfde pagina met ruimte voor extra kopregels, zodat de tabel niet
    /// tegen de kop aan komt te staan.
    func withExtraHeaderLines(_ count: Int) -> ReportPageGeometry {
        guard count > 0 else { return self }
        var copy = self
        copy.headerBlockHeight += Double(count) * headerLineHeight
        return copy
    }

    /// Eerste y-positie voor de tabelkop op een nieuwe pagina.
    var tableTop: Double { margin + headerBlockHeight }

    /// Hoeveel ritregels er op één pagina passen. Exact dezelfde afweging als
    /// de oude renderer maakte met zijn y-cursor.
    var rowsPerPage: Int {
        let firstRowY = tableTop + rowHeight
        let lastAllowedY = pageHeight - margin - bottomSlack - rowHeight
        guard lastAllowedY >= firstRowY else { return 1 }
        return Int(((lastAllowedY - firstRowY) / rowHeight).rounded(.down)) + 1
    }
}

struct SummaryEntry: Equatable, Sendable {
    var label: String
    var value: String
}

/// Volledig uitgerekend rapport: welke pagina's er zijn, welke rijen erop
/// staan en wat er in de samenvatting komt. Bevat geen tekenwerk en geen
/// UIKit, zodat de harness de inhoud van een PDF kan vergelijken zonder
/// simulator.
struct ReportDocumentPlan: Equatable, Sendable {
    struct Page: Equatable, Sendable {
        var title: String
        var meta: String
        /// Voertuig en kenteken; `nil` voor regio's die dat niet in de kop
        /// zetten (Nederland).
        var vehicleLine: String?
        var headers: [String]
        var rows: [[String]]
    }

    var pages: [Page]
    var summaryTitle: String
    var summaryEntries: [SummaryEntry]
    /// True als de samenvatting niet meer op de laatste tabelpagina paste en
    /// dus op een eigen pagina komt.
    var summaryOnOwnPage: Bool
    /// Volledige categorienamen bij de afkortingen in de tabel; leeg als de
    /// regio geen afkortingen gebruikt.
    var legendTitle: String?
    var legendEntries: [SummaryEntry]
    /// Waarschuwing wanneer de selectie meerdere voertuigen omvat en de
    /// kilometerreeks dus niet sluitend te tonen is.
    var note: String?
    var columnWidths: [Double]
    var geometry: ReportPageGeometry

    /// Bouwt het plan voor één regio. `generatedAt` wordt bewust doorgegeven
    /// in plaats van `.now` te gebruiken, zodat de uitvoer testbaar is.
    static func make(
        rows: [TripReportRow],
        summary: ReportSummary,
        ruleSet: any RegionRuleSet,
        periodLabel: String,
        generatedAt: Date,
        odometer: OdometerRange? = nil,
        baseGeometry: ReportPageGeometry = .a4Landscape
    ) -> ReportDocumentPlan {
        let layout = ruleSet.exportLayout
        let formatting = ruleSet.formatting
        let meta = "\(layout.periodLabelPrefix): \(periodLabel)"
            + " · \(layout.generatedAtLabel): \(formatting.date(generatedAt))"

        // Een Fahrtenbuch moet doorlopend en op datum zijn; sorteren gebeurt
        // hier zodat geen enkele aanroeper het kan vergeten.
        let rows = rows.sorted { $0.startDate < $1.startDate }

        // Voertuig en kenteken in de kop. Alleen zinvol bij één voertuig; bij
        // meerdere volgt hieronder een expliciete opmerking.
        let vehicles = ReportGenerator.vehicleNames(in: rows)
        var vehicleLine: String?
        var note: String?
        if let prefix = layout.vehicleHeaderPrefix {
            if vehicles.count == 1, let first = rows.first(where: { !$0.vehicleName.isEmpty }) {
                let plate = first.vehicleLicensePlate.isEmpty ? "" : " (\(first.vehicleLicensePlate))"
                vehicleLine = "\(prefix): \(first.vehicleName)\(plate)"
            } else if vehicles.count > 1 {
                vehicleLine = "\(prefix): \(vehicles.joined(separator: ", "))"
                note = layout.multipleVehiclesNote
            }
        }

        // De voertuigregel kost een extra kopregel; zonder die ruimte zou de
        // tabel ertegenaan komen te staan.
        let geometry = baseGeometry.withExtraHeaderLines(vehicleLine == nil ? 0 : 1)

        let valueRows = rows.map { ReportGenerator.values(for: $0, layout: layout, ruleSet: ruleSet) }
        let chunks = valueRows.isEmpty ? [[]] : valueRows.chunked(into: geometry.rowsPerPage)

        let pages = chunks.map { chunk in
            Page(
                title: layout.documentTitle, meta: meta, vehicleLine: vehicleLine,
                headers: layout.headers, rows: chunk
            )
        }

        // Past de samenvatting nog onder de laatste tabelpagina? Sommige
        // regio's willen 'm sowieso apart, als afsluitende verantwoording.
        let lastPageRows = Double(chunks.last?.count ?? 0)
        let yAfterRows = geometry.tableTop + geometry.rowHeight + lastPageRows * geometry.rowHeight
        let summaryOnOwnPage = layout.summaryAlwaysOnOwnPage
            || yAfterRows + geometry.summaryBlockHeight > geometry.pageHeight - geometry.margin

        // Legenda met de volledige categorienamen, omdat de tabelcel te smal
        // is voor "Fahrt zwischen Wohnung und erster Tätigkeitsstätte".
        let legendEntries: [SummaryEntry] = layout.legendTitle == nil ? [] :
            ruleSet.availableCategories.compactMap { category in
                let short = ruleSet.exportShortLabel(for: category)
                let full = ruleSet.exportLabel(for: category)
                guard short != full else { return nil }
                return SummaryEntry(label: short, value: full)
            }

        return ReportDocumentPlan(
            pages: pages,
            summaryTitle: layout.summaryTitle,
            summaryEntries: ReportGenerator
                .summaryLines(summary, layout: layout, ruleSet: ruleSet, odometer: odometer)
                .map { SummaryEntry(label: $0.label, value: $0.value) },
            summaryOnOwnPage: summaryOnOwnPage,
            legendTitle: layout.legendTitle,
            legendEntries: legendEntries,
            note: note,
            columnWidths: layout.columns.map(\.pdfWidth),
            geometry: geometry
        )
    }

    /// Leesbare weergave voor snapshot-vergelijking in de harness.
    var snapshotDescription: String {
        var lines: [String] = []
        for (index, page) in pages.enumerated() {
            lines.append("── pagina \(index + 1) ──")
            lines.append("titel:  \(page.title)")
            lines.append("meta:   \(page.meta)")
            if let vehicleLine = page.vehicleLine {
                lines.append("voertuig: \(vehicleLine)")
            }
            lines.append("kop:    \(page.headers.joined(separator: " | "))")
            for row in page.rows {
                lines.append("rij:    \(row.joined(separator: " | "))")
            }
        }
        lines.append("── \(summaryTitle)\(summaryOnOwnPage ? " (eigen pagina)" : "") ──")
        for entry in summaryEntries {
            lines.append("\(entry.label): \(entry.value)")
        }
        if let note {
            lines.append("opmerking: \(note)")
        }
        if let legendTitle, !legendEntries.isEmpty {
            lines.append("── \(legendTitle) ──")
            for entry in legendEntries {
                lines.append("\(entry.label) = \(entry.value)")
            }
        }
        lines.append("kolombreedtes: \(columnWidths.map { String(format: "%g", $0) }.joined(separator: ",")) (totaal \(String(format: "%g", columnWidths.reduce(0, +))))")
        lines.append("rijen per pagina: \(geometry.rowsPerPage)")
        return lines.joined(separator: "\n") + "\n"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
