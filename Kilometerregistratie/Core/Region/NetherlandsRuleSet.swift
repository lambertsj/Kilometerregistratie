import Foundation

/// De Nederlandse regelset: precies het gedrag dat de app vóór de
/// regio-abstractie had. Elke afwijking hier is een regressie voor bestaande
/// gebruikers — de golden files in `tools/goldens/` bewaken dat.
struct NetherlandsRuleSet: RegionRuleSet {
    var region: TaxRegion { .netherlands }

    var availableCategories: [TripCategory] { [.business, .commute, .personal] }

    /// Nederland kent geen per-categorie verplichte velden in de app: een rit
    /// is geldig zodra er een afstand is. Dat was de bestaande regel
    /// (`TripFormView.isValid`) en die blijft ongewijzigd.
    func requiredFields(for category: TripCategory) -> Set<TripField> {
        [.distance]
    }

    var enforcesOdometerContinuity: Bool { false }

    var requiresAuditTrail: Bool { false }

    var contemporaneousWindow: TimeInterval? { nil }

    /// De 500 km-privégrens voor leaserijders (bijtelling).
    var privateKmYearLimit: Double? { 500 }

    func exportLabel(for category: TripCategory) -> String {
        switch category {
        case .business: "Zakelijk"
        case .commute: "Woon-werk"
        case .personal: "Privé"
        }
    }

    var formatting: RegionFormatting { .dutch }

    func rates(forTaxYear taxYear: Int) -> RegionRates {
        TaxRates.netherlands.rates(for: taxYear)
    }

    /// Exact de kolommen, koppen, breedtes en samenvattingsregels van de
    /// bestaande export. Volgorde en spelling zijn vastgelegd in de goldens.
    var exportLayout: ExportLayout {
        ExportLayout(
            documentTitle: "Rittenregistratie",
            periodLabelPrefix: "Periode",
            generatedAtLabel: "Gegenereerd",
            columns: [
                ExportColumn(.date, header: "Datum", pdfWidth: 60),
                ExportColumn(.departureTime, header: "Vertrek", pdfWidth: 35),
                ExportColumn(.arrivalTime, header: "Aankomst", pdfWidth: 45),
                ExportColumn(.startAddress, header: "Beginadres", pdfWidth: 120),
                ExportColumn(.endAddress, header: "Eindadres", pdfWidth: 120),
                ExportColumn(.startOdometer, header: "Km-stand begin", pdfWidth: 50),
                ExportColumn(.endOdometer, header: "Km-stand eind", pdfWidth: 50),
                ExportColumn(.distanceKm, header: "Afstand (km)", pdfWidth: 45),
                ExportColumn(.category, header: "Categorie", pdfWidth: 60),
                ExportColumn(.note, header: "Doel/notitie", pdfWidth: 80),
                ExportColumn(.clientLabel, header: "Klant/project", pdfWidth: 50),
                ExportColumn(.vehicleName, header: "Voertuig", pdfWidth: 55),
            ],
            summaryTitle: "Samenvatting",
            summaryLines: [
                .tripCount(label: "Aantal ritten"),
                .totalKm(label: "Totaal"),
                .categoryKm(.business, label: "Zakelijk"),
                .categoryKm(.commute, label: "Woon-werk"),
                .categoryKm(.personal, label: "Privé"),
                .reimbursement(label: "Kilometervergoeding"),
            ],
            spreadsheetSummaryLines: [
                .tripCount(label: "Totaal aantal ritten"),
                .totalKm(label: "Totaal km"),
                .categoryKm(.business, label: "Zakelijk km"),
                .categoryKm(.commute, label: "Woon-werk km"),
                .categoryKm(.personal, label: "Privé km"),
                .reimbursement(label: "Kilometervergoeding (EUR)"),
            ],
            spreadsheetSheetName: "Ritten",
            customRangeSeparator: " t/m ",
            vehicleHeaderPrefix: nil,
            multipleVehiclesNote: nil,
            summaryAlwaysOnOwnPage: false,
            legendTitle: nil,
            fileNameStem: "Rittenregistratie"
        )
    }
}
