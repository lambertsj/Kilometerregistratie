import Foundation

/// De Duitse regelset voor een *ordnungsgemäßes Fahrtenbuch*.
///
/// Grondslag: § 6 Abs. 1 Nr. 4 Satz 3 EStG (auto in het Betriebsvermögen) en
/// § 8 Abs. 2 Satz 4 EStG voor werknemers met een firmawagen, uitgewerkt in
/// R 8.1 Abs. 9 Nr. 2 LStR. Die uitwerking bepaalt de per-categorie
/// verplichte velden hieronder.
///
/// De teksten in dit bestand zijn exportteksten (het document is voor het
/// Finanzamt) en volgen dus de regio, niet de UI-taal.
struct GermanyRuleSet: RegionRuleSet {
    var region: TaxRegion { .germany }

    var availableCategories: [TripCategory] { [.business, .commute, .personal] }

    /// Per categorie precies wat R 8.1 Abs. 9 Nr. 2 LStR vraagt — niet meer.
    ///
    /// De asymmetrie is bedoeld en staat letterlijk in de regeling: een
    /// privérit vraagt alleen de gereden kilometers, een woon-werkrit volstaat
    /// met een korte aantekening. Het sluitend zijn van de kilometerreeks is
    /// een *aparte* eis (`enforcesOdometerContinuity`) en wordt door de
    /// validatie afgedekt, niet door hier extra velden verplicht te maken.
    func requiredFields(for category: TripCategory) -> Set<TripField> {
        switch category {
        case .business:
            [
                .date,
                .startOdometer,
                .endOdometer,
                .destinationPlace,
                .destinationStreet,
                .purpose,
                .businessPartner,
            ]
        case .commute:
            [.date, .distance, .annotation]
        case .personal:
            [.date, .distance]
        }
    }

    var enforcesOdometerContinuity: Bool { true }

    var requiresAuditTrail: Bool { true }

    var contemporaneousWindow: TimeInterval? { TaxRates.germanContemporaneousWindow }

    /// Duitsland kent de Nederlandse 500 km-privégrens niet.
    var privateKmYearLimit: Double? { nil }

    func exportLabel(for category: TripCategory) -> String {
        switch category {
        case .business: "Geschäftsfahrt"
        case .commute: "Fahrt zwischen Wohnung und erster Tätigkeitsstätte"
        case .personal: "Privatfahrt"
        }
    }

    /// Verkorte vorm voor smalle tabelcellen; de volledige term staat in de
    /// legenda van het rapport.
    func exportShortLabel(for category: TripCategory) -> String {
        switch category {
        case .business: "Geschäftsfahrt"
        case .commute: "Wohnung/1. Tätigkeitsstätte"
        case .personal: "Privatfahrt"
        }
    }

    var formatting: RegionFormatting { .german }

    func rates(forTaxYear taxYear: Int) -> RegionRates {
        TaxRates.germany.rates(for: taxYear)
    }

    /// Een Fahrtenbuch bevat geen bedragen: het is een kilometerregistratie,
    /// geen declaratie. De vergoedingsregel ontbreekt daarom bewust in de
    /// samenvatting — de Entfernungspauschale voor woon-werk hoort in de
    /// aangifte, niet hier (zie `CommuteTreatment`).
    var exportLayout: ExportLayout {
        ExportLayout(
            documentTitle: "Fahrtenbuch",
            periodLabelPrefix: "Zeitraum",
            generatedAtLabel: "Erstellt am",
            columns: [
                ExportColumn(.date, header: "Datum", pdfWidth: 52),
                ExportColumn(.startOdometer, header: "Kilometerstand Abfahrt", pdfWidth: 55),
                ExportColumn(.endOdometer, header: "Kilometerstand Ankunft", pdfWidth: 55),
                ExportColumn(.distanceKm, header: "Gefahrene Kilometer", pdfWidth: 48),
                ExportColumn(.category, header: "Art der Fahrt", pdfWidth: 78),
                ExportColumn(.destinationPlace, header: "Reiseziel (Ort)", pdfWidth: 85),
                ExportColumn(.destinationStreet, header: "Reiseziel (Straße)", pdfWidth: 95),
                ExportColumn(.purpose, header: "Reisezweck", pdfWidth: 100),
                ExportColumn(.businessPartner, header: "Aufgesuchter Geschäftspartner", pdfWidth: 100),
                ExportColumn(.detourNote, header: "Umweg", pdfWidth: 55),
                ExportColumn(.vehicleName, header: "Fahrzeug", pdfWidth: 46),
            ],
            summaryTitle: "Zusammenfassung",
            summaryLines: [
                .tripCount(label: "Anzahl der Fahrten"),
                .odometerRange(label: "Kilometerstand"),
                .odometerDelta(label: "Gefahrene Kilometer im Zeitraum"),
                .totalKm(label: "Summe der erfassten Fahrten"),
                .categoryKm(.business, label: "Geschäftsfahrten"),
                .categoryKm(.commute, label: "Fahrten Wohnung/erste Tätigkeitsstätte"),
                .categoryKm(.personal, label: "Privatfahrten"),
                .unrecordedKm(label: "Differenz zum Kilometerstand"),
            ],
            spreadsheetSummaryLines: [
                .tripCount(label: "Anzahl der Fahrten"),
                .odometerDelta(label: "Gefahrene Kilometer im Zeitraum"),
                .totalKm(label: "Summe der erfassten Fahrten (km)"),
                .categoryKm(.business, label: "Geschäftsfahrten (km)"),
                .categoryKm(.commute, label: "Fahrten Wohnung/erste Tätigkeitsstätte (km)"),
                .categoryKm(.personal, label: "Privatfahrten (km)"),
                .unrecordedKm(label: "Differenz zum Kilometerstand (km)"),
            ],
            spreadsheetSheetName: "Fahrtenbuch",
            customRangeSeparator: " bis ",
            vehicleHeaderPrefix: "Fahrzeug",
            multipleVehiclesNote: "Die Auswahl umfasst mehrere Fahrzeuge. Ein Fahrtenbuch wird je Fahrzeug geführt; bitte je Fahrzeug einzeln exportieren.",
            summaryAlwaysOnOwnPage: true,
            legendTitle: "Legende",
            fileNameStem: "Fahrtenbuch"
        )
    }
}
