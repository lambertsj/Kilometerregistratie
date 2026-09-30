import Foundation

/// Tests op de regio-abstractie zelf: dat de Nederlandse regelset het oude
/// gedrag exact beschrijft, dat de Duitse de wettelijke velden vraagt, en dat
/// de tarieventabel zich als data gedraagt.
enum RegionRuleSetTests {
    static func run() {
        Harness.suite("Regio: NL verandert niets aan verplichte velden") {
            let dutch = NetherlandsRuleSet()
            // Vóór de refactor was de enige regel: afstand > 0. Geen enkele
            // categorie mag er een verplicht veld bij krijgen.
            for category in dutch.availableCategories {
                Harness.expectEqual(
                    dutch.requiredFields(for: category), [.distance],
                    "NL verplichte velden voor \(category.rawValue)"
                )
            }
            Harness.expect(!dutch.enforcesOdometerContinuity, "NL kent geen sluitende kilometerreeks")
            Harness.expect(!dutch.requiresAuditTrail, "NL kent geen audit trail")
            Harness.expect(dutch.contemporaneousWindow == nil, "NL kent geen zeitnah-venster")
            Harness.expectEqual(dutch.privateKmYearLimit, 500, "NL 500 km-grens")
        }

        Harness.suite("Regio: DE vraagt de velden uit R 8.1 Abs. 9 Nr. 2 LStR") {
            let germany = GermanyRuleSet()
            Harness.expectEqual(
                germany.requiredFields(for: .business),
                [.date, .startOdometer, .endOdometer, .destinationPlace, .destinationStreet, .purpose, .businessPartner],
                "DE zakelijke rit"
            )
            // De asymmetrie is wettelijk: privé alleen kilometers, woon-werk
            // een korte aantekening.
            Harness.expectEqual(germany.requiredFields(for: .personal), [.date, .distance], "DE privérit")
            Harness.expectEqual(germany.requiredFields(for: .commute), [.date, .distance, .annotation], "DE woon-werkrit")
            Harness.expect(germany.enforcesOdometerContinuity, "DE eist een sluitende kilometerreeks")
            Harness.expect(germany.requiresAuditTrail, "DE eist een audit trail")
            Harness.expectEqual(germany.contemporaneousWindow, 7 * 24 * 60 * 60, "DE zeitnah-venster")
            Harness.expect(germany.privateKmYearLimit == nil, "DE kent geen privékilometergrens")
        }

        Harness.suite("Regio: Duitse terminologie exact") {
            let germany = GermanyRuleSet()
            Harness.expectEqual(germany.exportLabel(for: .business), "Geschäftsfahrt", "Geschäftsfahrt")
            Harness.expectEqual(germany.exportLabel(for: .personal), "Privatfahrt", "Privatfahrt")
            Harness.expectEqual(
                germany.exportLabel(for: .commute),
                "Fahrt zwischen Wohnung und erster Tätigkeitsstätte",
                "volledige woon-werkterm"
            )
            let headers = germany.exportLayout.headers
            for term in ["Kilometerstand Abfahrt", "Reisezweck", "Aufgesuchter Geschäftspartner", "Umweg"] {
                Harness.expect(headers.contains(term), "kolom '\(term)' ontbreekt in het Fahrtenbuch")
            }
        }

        Harness.suite("Regio: elke categorie heeft een label in elke regio") {
            // Vangt op dat een nieuwe categorie of regio ergens vergeten wordt.
            for region in TaxRegion.allCases {
                let ruleSet = region.ruleSet
                for category in TripCategory.allCases {
                    Harness.expect(
                        !ruleSet.exportLabel(for: category).isEmpty,
                        "\(region.rawValue) mist een label voor \(category.rawValue)"
                    )
                    Harness.expect(
                        !ruleSet.exportShortLabel(for: category).isEmpty,
                        "\(region.rawValue) mist een kort label voor \(category.rawValue)"
                    )
                }
            }
        }

        Harness.suite("Regio: opmaak volgt de regio, niet de telefoon") {
            let german = RegionFormatting.german
            Harness.expectEqual(german.date(Fixtures.date(2026, 3, 2)), "02.03.2026", "DE-datumnotatie")
            Harness.expectEqual(german.number(1234.5, decimals: 1), "1.234,5", "DE duizendscheiding")
            Harness.expectEqual(german.distance(1234.5), "1.234,5 km", "DE afstand met eenheid")
            Harness.expectEqual(RegionFormatting.dutch.date(Fixtures.date(2026, 3, 2)), "02-03-2026", "NL-datumnotatie")
        }

        Harness.suite("Tarieven: jaargesleuteld, niet hardcoded") {
            let table = TaxRates.netherlands
            Harness.expectClose(table.rates(for: 2025).businessRatePerKm, 0.23, "NL 2025")
            // Een onbekend toekomstig jaar valt terug op het laatst bekende
            // jaar in plaats van op nul.
            Harness.expectClose(table.rates(for: 2099).businessRatePerKm, 0.23, "NL toekomstig jaar")
            Harness.expectEqual(table.rates(for: 2099).taxYear, 2026, "laatst bekende jaar")
            // Een jaar vóór de tabel valt terug op het oudste bekende jaar.
            Harness.expectEqual(table.rates(for: 1999).taxYear, 2024, "oudste bekende jaar")

            Harness.expectClose(TaxRates.germany.rates(for: 2025).businessRatePerKm, 0.30, "DE 2025")
            Harness.expectEqual(
                TaxRates.germany.rates(for: 2025).commuteTreatment,
                .distanceAllowanceOutsideScope,
                "DE woon-werk: Entfernungspauschale buiten scope"
            )
            Harness.expectEqual(
                TaxRates.netherlands.rates(for: 2025).commuteTreatment,
                .kilometresOnly,
                "NL woon-werk: alleen kilometers"
            )
        }

        Harness.suite("Regio: standaardvoorstel uit de toestelregio") {
            Harness.expectEqual(TaxRegion.suggested(for: "DE"), .germany, "DE-toestel")
            Harness.expectEqual(TaxRegion.suggested(for: "NL"), .netherlands, "NL-toestel")
            // Onbekend of afwezig valt terug op Nederland, zodat bestaande
            // gebruikers niet ineens de Duitse regels krijgen.
            Harness.expectEqual(TaxRegion.suggested(for: "FR"), .netherlands, "overige regio")
            Harness.expectEqual(TaxRegion.suggested(for: nil), .netherlands, "geen regio bekend")
        }

        Harness.suite("Regio: periodelabel volgt de regio") {
            Harness.expectEqual(PeriodFilter.quarter.exportLabel(for: .netherlands), "Dit kwartaal", "NL")
            Harness.expectEqual(PeriodFilter.quarter.exportLabel(for: .germany), "Laufendes Quartal", "DE")
        }

        Harness.suite("Regio: Duitse export gebruikt Duitse opmaak") {
            let germany: any RegionRuleSet = GermanyRuleSet()
            let csv = ReportGenerator.csv(rows: Fixtures.dutchRows, ruleSet: germany)
            Harness.expect(csv.hasPrefix("Datum;Kilometerstand Abfahrt;"), "Duitse kolomkoppen")
            Harness.expect(csv.contains("02.03.2026"), "Duitse datumnotatie in de export")
            Harness.expect(csv.contains("50.000"), "Duitse duizendscheiding")
            Harness.expect(!csv.contains("Zakelijk"), "geen Nederlandse categorienamen in een Duitse export")
            Harness.expect(csv.contains("Geschäftsfahrt"), "Duitse categorienaam")
        }
    }
}
