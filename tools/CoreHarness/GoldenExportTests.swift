import Foundation

/// Vastleggen van de Nederlandse export zoals die vóór de regio-refactor was.
/// Deze goldens zijn het contract: ze mogen niet wijzigen. Als een van deze
/// checks faalt is dat per definitie een regressie voor bestaande NL-gebruikers.
enum GoldenExportTests {
    /// De Nederlandse regelset, expliciet: de export mag nooit van
    /// `Locale.current` afhangen.
    private static let dutch: any RegionRuleSet = NetherlandsRuleSet()

    static func run() {
        Harness.suite("NL-export golden: CSV") {
            let csv = ReportGenerator.csv(rows: Fixtures.dutchRows, ruleSet: dutch)
            Harness.expectMatchesGolden(csv, golden: "nl-report.csv")
        }

        Harness.suite("NL-export golden: XLSX bytes") {
            let summary = ReportGenerator.summary(rows: Fixtures.dutchRows, ratePerKm: 0.23)
            let workbook = XlsxBuilder.workbook(rows: Fixtures.dutchRows, summary: summary, ruleSet: dutch)
            Harness.expectMatchesGolden(workbook, golden: "nl-report.xlsx")
        }

        Harness.suite("NL-export golden: XLSX sheet-XML") {
            // Naast de bytes ook de sheet als leesbare golden, zodat een
            // onbedoelde wijziging in een review zichtbaar is en niet alleen
            // als "N bytes verschillen".
            let summary = ReportGenerator.summary(rows: Fixtures.dutchRows, ratePerKm: 0.23)
            let workbook = XlsxBuilder.workbook(rows: Fixtures.dutchRows, summary: summary, ruleSet: dutch)
            guard let sheet = ZipReader.entry("xl/worksheets/sheet1.xml", in: workbook) else {
                Harness.expect(false, "sheet1.xml niet gevonden in de xlsx")
                return
            }
            let readable = String(decoding: sheet, as: UTF8.self)
                .replacingOccurrences(of: "><", with: ">\n<")
            Harness.expectMatchesGolden(readable, golden: "nl-report-sheet1.xml")
        }

        Harness.suite("NL-export golden: kolomkoppen") {
            // De kolomvolgorde is de fiscale layout; die moet exact blijven.
            Harness.expectEqual(
                dutch.exportLayout.headers.joined(separator: "|"),
                "Datum|Vertrek|Aankomst|Beginadres|Eindadres|Km-stand begin|Km-stand eind"
                    + "|Afstand (km)|Categorie|Doel/notitie|Klant/project|Voertuig",
                "NL-kolomkoppen"
            )
        }

        Harness.suite("NL-export golden: totalen") {
            let summary = ReportGenerator.summary(rows: Fixtures.dutchRows, ratePerKm: 0.23)
            Harness.expectEqual(summary.tripCount, 3, "aantal ritten")
            Harness.expectClose(summary.totalKm, 50, "totaal km")
            Harness.expectClose(summary.businessKm, 30, "zakelijk km")
            Harness.expectClose(summary.commuteKm, 7.5, "woon-werk km")
            Harness.expectClose(summary.personalKm, 12.5, "privé km")
            Harness.expectClose(summary.reimbursement, 6.9, "vergoeding")
        }

        Harness.suite("NL-export golden: formattering") {
            // Deze exacte vormen zijn wat de NL-export nu produceert:
            // decimale komma, duizend-punt op kilometerstanden, dd-MM-yyyy.
            Harness.expectEqual(dutch.formatting.number(30, decimals: 1), "30,0", "afstand 1 decimaal")
            Harness.expectEqual(dutch.formatting.number(50_000, decimals: 0), "50.000", "km-stand met duizend-punt")
            Harness.expectEqual(dutch.formatting.number(6.9, decimals: 2), "6,90", "bedrag 2 decimalen")
            Harness.expectEqual(
                dutch.formatting.date(Fixtures.date(2026, 3, 2)),
                "02-03-2026", "NL-datumnotatie"
            )
        }

        Harness.suite("NL-export golden: rit over middernacht") {
            let csv = ReportGenerator.csv(rows: [Fixtures.overnightRow], ruleSet: dutch)
            Harness.expect(
                csv.contains("02-03-2026;23:30;00:45"),
                "datum blijft die van vertrek, aankomsttijd is van de volgende dag"
            )
        }
    }
}
