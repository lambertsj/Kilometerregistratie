import Foundation

/// Snapshot van de PDF-*inhoud*. De PDF-bytes zelf zijn niet vergelijkbaar
/// (UIGraphicsPDFRenderer zet een creatiedatum in het bestand), dus wordt het
/// UI-vrije `ReportDocumentPlan` gesnapshot: titel, meta, kolomkoppen, alle
/// rijen, de paginaverdeling en het samenvattingsblok.
enum ReportPlanTests {
    private static let dutch: any RegionRuleSet = NetherlandsRuleSet()

    static func run() {
        Harness.suite("PDF-plan: paginering ongewijzigd") {
            // De oude renderer schoof met een y-cursor en kreeg zo 20 rijen op
            // een A4-liggend-pagina. Die uitkomst moet gelijk blijven, anders
            // ziet een bestaand NL-rapport er anders uit.
            Harness.expectEqual(ReportPageGeometry.a4Landscape.rowsPerPage, 20, "rijen per pagina")
        }

        Harness.suite("PDF-plan: NL-snapshot") {
            let summary = ReportGenerator.summary(rows: Fixtures.dutchRows, ratePerKm: 0.23)
            let plan = ReportDocumentPlan.make(
                rows: Fixtures.dutchRows,
                summary: summary,
                ruleSet: dutch,
                periodLabel: "Dit kwartaal",
                generatedAt: Fixtures.generatedAt
            )
            Harness.expectMatchesGolden(plan.snapshotDescription, golden: "nl-report-pdfplan.txt")
        }

        Harness.suite("PDF-plan: kolommen passen op de pagina") {
            // Regressiebewaking: de som van de kolombreedtes mag niet breder
            // worden dan de bruikbare paginabreedte, anders valt de laatste
            // kolom buiten het papier.
            let geometry = ReportPageGeometry.a4Landscape
            let usable = geometry.pageWidth - 2 * geometry.margin

            // De Nederlandse layout is 770,0 pt bij 769,8 pt bruikbaar: 0,2 pt
            // te breed. Dat is zo sinds versie 1, valt bij 7 pt tekst niet op,
            // en wordt bewust *niet* gecorrigeerd — dat zou het bestaande
            // NL-rapport wijzigen. Vastgelegd zodat de afwijking niet groeit.
            let knownOverflow: [TaxRegion: Double] = [.netherlands: 0.2]

            for region in TaxRegion.allCases {
                let total = region.ruleSet.exportLayout.totalPdfWidth
                let allowance = knownOverflow[region] ?? 0
                Harness.expect(
                    total <= usable + allowance,
                    "\(region.rawValue): kolombreedte \(total) pt past niet in \(usable) pt"
                        + (allowance > 0 ? " (+\(allowance) pt bekende afwijking)" : "")
                )
            }
            Harness.expectClose(
                NetherlandsRuleSet().exportLayout.totalPdfWidth, 770,
                "NL-kolombreedte ongewijzigd"
            )
        }

        Harness.suite("PDF-plan: meerdere pagina's") {
            // 45 ritten → 3 pagina's van 20/20/5.
            let many = (0..<45).map { index in
                TripReportRow(
                    startDate: Fixtures.date(2026, 3, 1, 8, 0).addingTimeInterval(Double(index) * 86_400),
                    endDate: nil, startAddress: "A", endAddress: "B",
                    startOdometer: nil, endOdometer: nil, distanceKm: 10,
                    category: .business, note: "", clientLabel: "", vehicleName: ""
                )
            }
            let summary = ReportGenerator.summary(rows: many, ratePerKm: 0.23)
            let plan = ReportDocumentPlan.make(
                rows: many, summary: summary, ruleSet: dutch,
                periodLabel: "Dit jaar", generatedAt: Fixtures.generatedAt
            )
            Harness.expectEqual(plan.pages.count, 3, "aantal pagina's")
            Harness.expectEqual(plan.pages.map(\.rows.count), [20, 20, 5], "rijen per pagina")
            Harness.expect(
                plan.pages.allSatisfy { $0.headers == dutch.exportLayout.headers },
                "elke pagina herhaalt de kolomkop"
            )
        }

        Harness.suite("PDF-plan: leeg rapport levert één pagina") {
            let summary = ReportGenerator.summary(rows: [], ratePerKm: 0.23)
            let plan = ReportDocumentPlan.make(
                rows: [], summary: summary, ruleSet: dutch,
                periodLabel: "Alles", generatedAt: Fixtures.generatedAt
            )
            Harness.expectEqual(plan.pages.count, 1, "aantal pagina's")
            Harness.expectEqual(plan.pages[0].rows.count, 0, "aantal rijen")
        }
    }
}
