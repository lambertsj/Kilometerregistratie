import Foundation

/// Tests op het Duitse Fahrtenbuch-rapport: doorlopende rijen op datum,
/// kilometerstanden per rit, de verplichte annotatiekolommen, en een
/// samenvatting die aansluit op de kilometerteller.
enum GermanExportTests {
    private static let germany: any RegionRuleSet = GermanyRuleSet()

    /// Eén voertuig, een sluitende reeks, alle drie de categorieën.
    static let rows: [TripReportRow] = [
        TripReportRow(
            startDate: Fixtures.date(2026, 3, 2, 8, 15), endDate: Fixtures.date(2026, 3, 2, 9, 5),
            startAddress: "Musterweg 1", endAddress: "Leopoldstraße 12",
            startOdometer: 48_000, endOdometer: 48_210, distanceKm: 210,
            category: .business, note: "", clientLabel: "",
            vehicleName: "Firmenwagen", vehicleLicensePlate: "M-AB 1234",
            destinationPlace: "München", destinationStreet: "Leopoldstraße 12",
            purpose: "Projektbesprechung", businessPartner: "Meier GmbH", detourNote: ""
        ),
        TripReportRow(
            startDate: Fixtures.date(2026, 3, 3, 7, 50), endDate: Fixtures.date(2026, 3, 3, 8, 20),
            startAddress: "", endAddress: "",
            startOdometer: 48_210, endOdometer: 48_235, distanceKm: 25,
            category: .commute, note: "Büro", clientLabel: "",
            vehicleName: "Firmenwagen", vehicleLicensePlate: "M-AB 1234"
        ),
        TripReportRow(
            startDate: Fixtures.date(2026, 3, 4, 19, 40), endDate: Fixtures.date(2026, 3, 4, 20, 10),
            startAddress: "", endAddress: "",
            startOdometer: 48_235, endOdometer: 48_248, distanceKm: 13,
            category: .personal, note: "", clientLabel: "",
            vehicleName: "Firmenwagen", vehicleLicensePlate: "M-AB 1234"
        ),
    ]

    static func run() {
        Harness.suite("DE-rapport: snapshot") {
            let summary = ReportGenerator.summary(rows: rows, ratePerKm: 0.30)
            let plan = ReportDocumentPlan.make(
                rows: rows, summary: summary, ruleSet: germany,
                periodLabel: PeriodFilter.quarter.exportLabel(for: .germany),
                generatedAt: Fixtures.generatedAt,
                odometer: ReportGenerator.odometerRange(for: rows)
            )
            Harness.expectMatchesGolden(plan.snapshotDescription, golden: "de-report-pdfplan.txt")
        }

        Harness.suite("DE-rapport: voertuig en kenteken in de kop") {
            let summary = ReportGenerator.summary(rows: rows, ratePerKm: 0.30)
            let plan = ReportDocumentPlan.make(
                rows: rows, summary: summary, ruleSet: germany,
                periodLabel: "Laufendes Quartal", generatedAt: Fixtures.generatedAt
            )
            Harness.expectEqual(
                plan.pages.first?.vehicleLine, "Fahrzeug: Firmenwagen (M-AB 1234)",
                "voertuigregel"
            )
            Harness.expect(
                plan.pages.first?.meta.contains("Zeitraum: Laufendes Quartal") == true,
                "periode in de kop"
            )
            // Nederland houdt zijn kop van één regel.
            let dutchPlan = ReportDocumentPlan.make(
                rows: Fixtures.dutchRows,
                summary: ReportGenerator.summary(rows: Fixtures.dutchRows, ratePerKm: 0.23),
                ruleSet: NetherlandsRuleSet(), periodLabel: "Dit kwartaal",
                generatedAt: Fixtures.generatedAt
            )
            Harness.expect(dutchPlan.pages.first?.vehicleLine == nil, "NL zet geen voertuig in de kop")
        }

        Harness.suite("DE-rapport: kilometerstanden sluiten aan") {
            let summary = ReportGenerator.summary(rows: rows, ratePerKm: 0.30)
            guard let odometer = ReportGenerator.odometerRange(for: rows) else {
                Harness.expect(false, "kilometerbereik moet bepaald kunnen worden")
                return
            }
            Harness.expectClose(odometer.start, 48_000, "beginstand")
            Harness.expectClose(odometer.end, 48_248, "eindstand")
            Harness.expectClose(odometer.delta, 248, "gereden kilometers volgens de teller")
            // De drie categorieën tellen op tot het totaal …
            Harness.expectClose(
                summary.businessKm + summary.commuteKm + summary.personalKm, summary.totalKm,
                "categorieën tellen op tot het totaal"
            )
            // … en het totaal sluit op de kilometerteller.
            Harness.expectClose(odometer.delta - summary.totalKm, 0, "geen onverklaarde kilometers")
        }

        Harness.suite("DE-rapport: onverklaarde kilometers worden getoond") {
            // Haal de middelste rit weg: er ontbreken dan 25 km die de teller
            // wél telt. Dat moet zichtbaar zijn, niet weggerekend.
            let incomplete = [rows[0], rows[2]]
            let summary = ReportGenerator.summary(rows: incomplete, ratePerKm: 0.30)
            let odometer = ReportGenerator.odometerRange(for: incomplete)
            let lines = ReportGenerator.summaryLines(
                summary, layout: germany.exportLayout, ruleSet: germany, odometer: odometer
            )
            let difference = lines.first { $0.label == "Differenz zum Kilometerstand" }
            Harness.expectEqual(difference?.value, "25,0 km", "onverklaarde kilometers zichtbaar")
        }

        Harness.suite("DE-rapport: meerdere voertuigen levert geen schijnbare aansluiting") {
            var other = rows[0]
            other.vehicleName = "Zweitwagen"
            other.vehicleLicensePlate = "M-CD 5678"
            let mixed = rows + [other]

            Harness.expect(
                ReportGenerator.odometerRange(for: mixed) == nil,
                "bij meerdere voertuigen is er geen sluitende reeks"
            )
            let plan = ReportDocumentPlan.make(
                rows: mixed, summary: ReportGenerator.summary(rows: mixed, ratePerKm: 0.30),
                ruleSet: germany, periodLabel: "Laufendes Quartal", generatedAt: Fixtures.generatedAt,
                odometer: ReportGenerator.odometerRange(for: mixed)
            )
            Harness.expect(plan.note != nil, "er moet een opmerking over meerdere voertuigen staan")
            Harness.expect(
                !plan.summaryEntries.contains { $0.label == "Kilometerstand" },
                "geen kilometerstandregel zonder sluitende reeks"
            )
        }

        Harness.suite("DE-rapport: rijen staan doorlopend op datum") {
            // Ook als de aanroeper ze door elkaar aanlevert.
            let shuffled = [rows[2], rows[0], rows[1]]
            let plan = ReportDocumentPlan.make(
                rows: shuffled, summary: ReportGenerator.summary(rows: shuffled, ratePerKm: 0.30),
                ruleSet: germany, periodLabel: "Laufendes Quartal", generatedAt: Fixtures.generatedAt
            )
            let dates = plan.pages.flatMap(\.rows).map { $0[0] }
            Harness.expectEqual(dates, ["02.03.2026", "03.03.2026", "04.03.2026"], "chronologische volgorde")
        }

        Harness.suite("DE-rapport: Duitse opmaak in elke cel") {
            let plan = ReportDocumentPlan.make(
                rows: rows, summary: ReportGenerator.summary(rows: rows, ratePerKm: 0.30),
                ruleSet: germany, periodLabel: "Laufendes Quartal", generatedAt: Fixtures.generatedAt,
                odometer: ReportGenerator.odometerRange(for: rows)
            )
            let flat = plan.snapshotDescription
            Harness.expect(flat.contains("02.03.2026"), "dd.MM.yyyy")
            Harness.expect(flat.contains("48.000"), "duizendscheiding met punt")
            Harness.expect(flat.contains("248,0 km"), "decimale komma met eenheid")
            Harness.expect(!flat.contains("02-03-2026"), "geen Nederlandse datumnotatie")
        }

        Harness.suite("DE-rapport: verplichte kolommen aanwezig en gevuld") {
            let plan = ReportDocumentPlan.make(
                rows: rows, summary: ReportGenerator.summary(rows: rows, ratePerKm: 0.30),
                ruleSet: germany, periodLabel: "Laufendes Quartal", generatedAt: Fixtures.generatedAt
            )
            guard let headers = plan.pages.first?.headers,
                  let businessRow = plan.pages.first?.rows.first else {
                Harness.expect(false, "verwachtte een pagina met rijen")
                return
            }
            // Elke rit heeft begin- én eindstand.
            for (index, row) in (plan.pages.first?.rows ?? []).enumerated() {
                let start = headers.firstIndex(of: "Kilometerstand Abfahrt") ?? 0
                let end = headers.firstIndex(of: "Kilometerstand Ankunft") ?? 0
                Harness.expect(!row[start].isEmpty, "rij \(index + 1) mist de beginstand")
                Harness.expect(!row[end].isEmpty, "rij \(index + 1) mist de eindstand")
            }
            // De zakelijke rit heeft de verplichte annotaties.
            for column in ["Reiseziel (Ort)", "Reiseziel (Straße)", "Reisezweck", "Aufgesuchter Geschäftspartner"] {
                guard let index = headers.firstIndex(of: column) else {
                    Harness.expect(false, "kolom \(column) ontbreekt")
                    continue
                }
                Harness.expect(!businessRow[index].isEmpty, "kolom \(column) is leeg bij een zakelijke rit")
            }
        }

        Harness.suite("DE-rapport: samenvatting op een eigen pagina met legenda") {
            let plan = ReportDocumentPlan.make(
                rows: rows, summary: ReportGenerator.summary(rows: rows, ratePerKm: 0.30),
                ruleSet: germany, periodLabel: "Laufendes Quartal", generatedAt: Fixtures.generatedAt,
                odometer: ReportGenerator.odometerRange(for: rows)
            )
            Harness.expect(plan.summaryOnOwnPage, "de verantwoording staat op een eigen pagina")
            Harness.expectEqual(plan.legendTitle, "Legende", "legendakop")
            Harness.expect(
                plan.legendEntries.contains {
                    $0.value == "Fahrt zwischen Wohnung und erster Tätigkeitsstätte"
                },
                "de volledige woon-werkterm staat in de legenda"
            )
            // Nederland houdt het bestaande gedrag: samenvatting stroomt mee.
            let dutchPlan = ReportDocumentPlan.make(
                rows: Fixtures.dutchRows,
                summary: ReportGenerator.summary(rows: Fixtures.dutchRows, ratePerKm: 0.23),
                ruleSet: NetherlandsRuleSet(), periodLabel: "Dit kwartaal",
                generatedAt: Fixtures.generatedAt
            )
            Harness.expect(!dutchPlan.summaryOnOwnPage, "NL zet de samenvatting niet apart")
            Harness.expect(dutchPlan.legendEntries.isEmpty, "NL heeft geen legenda")
        }

        Harness.suite("DE-rapport: gebroken kilometerstand blijft consistent") {
            // Kilometerstanden worden per hele kilometer getoond. Staat er
            // toch een halve in de data (oudere of geïmporteerde ritten), dan
            // zou de getoonde reeks niet meer kloppen met het verschil.
            // Vastgelegd zodat de afwijking zichtbaar is en niet verrast.
            var fractional = rows[2]
            fractional.startOdometer = 48_235
            fractional.endOdometer = 48_247.5
            fractional.distanceKm = 12.5
            let set = [rows[0], rows[1], fractional]
            let summary = ReportGenerator.summary(rows: set, ratePerKm: 0.30)
            let odometer = ReportGenerator.odometerRange(for: set)
            let lines = ReportGenerator.summaryLines(
                summary, layout: germany.exportLayout, ruleSet: germany, odometer: odometer
            )
            let range = lines.first { $0.label == "Kilometerstand" }?.value
            let delta = lines.first { $0.label == "Gefahrene Kilometer im Zeitraum" }?.value
            // De getoonde eindstand is afgerond, het verschil niet: 48.248 −
            // 48.000 is 248, terwijl er 247,5 staat. In de praktijk voert de
            // gebruiker hele kilometers in (het invoerveld rondt daarop af),
            // dus dit treedt alleen op bij geïmporteerde data.
            Harness.expectEqual(range, "48.000 – 48.248", "getoonde reeks")
            Harness.expectEqual(delta, "247,5 km", "werkelijk verschil")
            Harness.expectEqual(
                lines.first { $0.label == "Differenz zum Kilometerstand" }?.value, "0,0 km",
                "de registratie sluit nog steeds op de werkelijke standen"
            )
        }

        Harness.suite("DE-rapport: geen bedragen in het Fahrtenbuch") {
            // Een Fahrtenbuch is een kilometerregistratie, geen declaratie.
            let plan = ReportDocumentPlan.make(
                rows: rows, summary: ReportGenerator.summary(rows: rows, ratePerKm: 0.30),
                ruleSet: germany, periodLabel: "Laufendes Quartal", generatedAt: Fixtures.generatedAt,
                odometer: ReportGenerator.odometerRange(for: rows)
            )
            Harness.expect(
                !plan.snapshotDescription.contains("€"),
                "er hoort geen bedrag in te staan"
            )
        }

        Harness.suite("DE-export: CSV en xlsx volgen dezelfde layout") {
            let summary = ReportGenerator.summary(rows: rows, ratePerKm: 0.30)
            let odometer = ReportGenerator.odometerRange(for: rows)
            let csv = ReportGenerator.csv(rows: rows, ruleSet: germany)
            Harness.expectMatchesGolden(csv, golden: "de-report.csv")

            let workbook = XlsxBuilder.workbook(
                rows: rows, summary: summary, ruleSet: germany, odometer: odometer
            )
            Harness.expectEqual(workbook.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]), "geldige zip")
            guard let sheet = ZipReader.entry("xl/worksheets/sheet1.xml", in: workbook) else {
                Harness.expect(false, "sheet1.xml ontbreekt")
                return
            }
            let text = String(decoding: sheet, as: UTF8.self)
            Harness.expect(text.contains("Kilometerstand Abfahrt"), "Duitse kolomkop in de xlsx")
            Harness.expect(text.contains("Differenz zum Kilometerstand"), "aansluiting in de xlsx")
        }
    }
}
