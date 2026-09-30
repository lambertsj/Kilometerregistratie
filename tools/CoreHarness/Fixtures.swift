import Foundation

/// Vaste, tijdzone-onafhankelijke testdata. Alle datums worden in
/// Europe/Amsterdam gebouwd zodat de golden files reproduceerbaar zijn,
/// ongeacht de tijdzone van de machine die de harness draait.
enum Fixtures {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Vast "gegenereerd op"-moment, zodat exports met een tijdstempel
    /// deterministisch zijn (geen `.now` in de renderers).
    static let generatedAt = date(2026, 4, 1, 10, 30)

    /// De Nederlandse referentieset: een zakelijke rit met puntkomma en
    /// aanhalingstekens in de tekstvelden (CSV-escaping), een privérit zonder
    /// eindtijd/kilometerstanden, en een woon-werkrit met een halve kilometer.
    static let dutchRows: [TripReportRow] = [
        TripReportRow(
            startDate: date(2026, 3, 2, 8, 15), endDate: date(2026, 3, 2, 9, 5),
            startAddress: "Thuisstraat 1; Dorp", endAddress: "Kantoorlaan 5, Amsterdam",
            startOdometer: 50_000, endOdometer: 50_030, distanceKm: 30,
            category: .business, note: "Klantbezoek \"Jansen\"", clientLabel: "Jansen BV",
            vehicleName: "Bedrijfsauto"
        ),
        TripReportRow(
            startDate: date(2026, 3, 3, 19, 40), endDate: nil,
            startAddress: "", endAddress: "",
            startOdometer: nil, endOdometer: nil, distanceKm: 12.5,
            category: .personal, note: "", clientLabel: "", vehicleName: ""
        ),
        TripReportRow(
            startDate: date(2026, 3, 4, 7, 50), endDate: date(2026, 3, 4, 8, 20),
            startAddress: "Thuisstraat 1", endAddress: "Kantoorlaan 5",
            startOdometer: 50_030, endOdometer: 50_037.5, distanceKm: 7.5,
            category: .commute, note: "", clientLabel: "", vehicleName: "Bedrijfsauto"
        ),
    ]

    /// Rit over middernacht: de datum blijft die van vertrek.
    static let overnightRow = TripReportRow(
        startDate: date(2026, 3, 2, 23, 30), endDate: date(2026, 3, 3, 0, 45),
        startAddress: "Kantoor", endAddress: "Thuis",
        startOdometer: nil, endOdometer: nil, distanceKm: 40,
        category: .business, note: "", clientLabel: "", vehicleName: ""
    )
}
