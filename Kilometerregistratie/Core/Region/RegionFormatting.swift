import Foundation

/// Locale-correcte opmaak voor exports, met een *expliciete* locale in plaats
/// van `Locale.current`: een exportbestand moet de notatie van de fiscale
/// regio volgen, niet die van de telefoontaal.
///
/// Alles loopt via `FormatStyle`, nooit via string-interpolatie van getallen.
/// De patronen zijn `verbatim` zodat de datumnotatie exact vastligt
/// (`dd-MM-yyyy` voor NL, `dd.MM.yyyy` voor DE) en niet meebeweegt met
/// wijzigingen in de ICU-data.
struct RegionFormatting: Sendable {
    let locale: Locale
    /// Vast datumpatroon: `dd-MM-yyyy` (NL) of `dd.MM.yyyy` (DE).
    let dateFormat: Date.FormatString
    let currencyCode: String
    /// Veldscheidingsteken voor CSV. Zowel Nederlands als Duits Excel
    /// verwachten een puntkomma, omdat de komma het decimaalteken is.
    let csvSeparator: String

    // De tijdzone en kalender worden per aanroep gelezen, precies zoals de
    // oude `DateFormatter` deed (die `TimeZone.current` gebruikte). Zo blijft
    // de Nederlandse uitvoer byte-identiek.
    private var timeZone: TimeZone { .current }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    // MARK: - Datum en tijd

    func date(_ date: Date) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: dateFormat,
                locale: locale,
                timeZone: timeZone,
                calendar: calendar
            )
        )
    }

    func time(_ date: Date) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                locale: locale,
                timeZone: timeZone,
                calendar: calendar
            )
        )
    }

    // MARK: - Getallen

    /// Getal met een vast aantal decimalen en duizendscheiding.
    ///
    /// De afrondingsregel blijft bewust de standaard (`toNearestOrEven`): dat
    /// is wat `String(format: "%.Nf")` óók deed, en dus wat de bestaande
    /// Nederlandse exports al jaren produceren. `toNearestOrAwayFromZero`
    /// zou kilometerstanden op `,5` stilletjes anders afronden.
    func number(_ value: Double, decimals: Int) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(decimals))
                .grouping(.automatic)
                .locale(locale)
        )
    }

    /// Afstand met eenheid, bv. "1.234,5 km".
    func distance(_ km: Double, decimals: Int = 1) -> String {
        "\(number(km, decimals: decimals)) km"
    }

    func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale))
    }

    // MARK: - Regiovarianten

    static let dutch = RegionFormatting(
        locale: Locale(identifier: "nl_NL"),
        dateFormat: "\(day: .twoDigits)-\(month: .twoDigits)-\(year: .defaultDigits)",
        currencyCode: "EUR",
        csvSeparator: ";"
    )

    static let german = RegionFormatting(
        locale: Locale(identifier: "de_DE"),
        dateFormat: "\(day: .twoDigits).\(month: .twoDigits).\(year: .defaultDigits)",
        currencyCode: "EUR",
        csvSeparator: ";"
    )
}
