import Foundation

/// Alles wat per fiscale regio verschilt, achter één protocol. Als er ergens
/// anders in de app een `if region == .germany` nodig lijkt, hoort het gedrag
/// hier thuis.
///
/// Let op de taal van exports: een rapport is een document voor de
/// belastingdienst van die *regio*, dus de kolomkoppen en categorienamen erin
/// volgen de regio en niet de UI-taal. Ze staan daarom als vaste strings in de
/// regelsets en gaan bewust niet door de String Catalog.
protocol RegionRuleSet: Sendable {
    var region: TaxRegion { get }

    /// De ritcategorieën die deze regio onderscheidt, in weergaveorde.
    var availableCategories: [TripCategory] { get }

    /// Welke velden een rit van deze categorie moet hebben om compleet te zijn.
    func requiredFields(for category: TripCategory) -> Set<TripField>

    /// Moet de kilometerstand een sluitende, aaneengesloten reeks vormen?
    var enforcesOdometerContinuity: Bool { get }

    /// Moeten wijzigingen bijgehouden en bewaard worden (en is hard verwijderen
    /// dus verboden)?
    var requiresAuditTrail: Bool { get }

    /// Venster waarbinnen een wijziging als "tijdig" geldt; `nil` als de regio
    /// hier geen eis stelt.
    var contemporaneousWindow: TimeInterval? { get }

    /// Jaargrens voor privékilometers (NL: de 500 km-regel). `nil` als de regio
    /// dit begrip niet kent.
    var privateKmYearLimit: Double? { get }

    /// De naam van deze categorie zoals die in een export van deze regio staat.
    func exportLabel(for category: TripCategory) -> String

    /// Verkorte variant voor smalle tabelcellen. Standaard gelijk aan
    /// `exportLabel`; alleen regio's met lange wettelijke termen wijken af.
    func exportShortLabel(for category: TripCategory) -> String

    var exportLayout: ExportLayout { get }

    var formatting: RegionFormatting { get }

    func rates(forTaxYear taxYear: Int) -> RegionRates
}

extension RegionRuleSet {
    func exportShortLabel(for category: TripCategory) -> String {
        exportLabel(for: category)
    }

    /// Is dit veld verplicht voor deze categorie?
    func isRequired(_ field: TripField, for category: TripCategory) -> Bool {
        requiredFields(for: category).contains(field)
    }

    /// Alle velden die de regio in *enige* categorie kan vragen. Handig voor
    /// de UI, om te bepalen welke invoervelden zichtbaar moeten zijn.
    var allRelevantFields: Set<TripField> {
        availableCategories.reduce(into: Set<TripField>()) { result, category in
            result.formUnion(requiredFields(for: category))
        }
    }
}
