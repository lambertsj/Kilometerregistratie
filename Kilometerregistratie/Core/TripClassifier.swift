import Foundation

/// Werktijden voor de kantooruren-regel, als puur waardetype zodat de
/// classificatielogica zonder SwiftData testbaar is.
struct WorkSchedule: Equatable {
    var enabled: Bool
    /// Minuten sinds middernacht.
    var startMinute: Int
    var endMinute: Int
    /// Calendar.weekday-waarden (1 = zondag … 7 = zaterdag).
    var weekdays: Set<Int>

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let weekday = calendar.component(.weekday, from: date)
        guard weekdays.contains(weekday) else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return minute >= startMinute && minute < endMinute
    }
}

extension AppSettings {
    var workSchedule: WorkSchedule {
        WorkSchedule(
            enabled: workHoursEnabled,
            startMinute: workDayStartMinute,
            endMinute: workDayEndMinute,
            weekdays: workWeekdays
        )
    }
}

/// Regelgebaseerde categorie-suggestie. Bewust simpel en lokaal (geen ML),
/// maar met een prioriteitsvolgorde die later uitbreidbaar is:
/// 1. Zelflerend: eerder gekozen categorie voor dezelfde adrescombinatie.
/// 2. Kantooruren-regel: binnen werktijd zakelijk, erbuiten privé.
/// 3. Standaard zakelijk (declaratie-flow moet het snelst zijn).
enum TripClassifier {
    static func suggestCategory(
        startDate: Date,
        learned: TripCategory?,
        schedule: WorkSchedule,
        calendar: Calendar = .current
    ) -> TripCategory {
        if let learned {
            return learned
        }
        if schedule.enabled {
            return schedule.contains(startDate, calendar: calendar) ? .business : .personal
        }
        return .business
    }

    /// Genormaliseerde sleutel voor een adrescombinatie; nil zolang niet
    /// beide adressen ingevuld zijn.
    static func routeKey(startAddress: String, endAddress: String) -> String? {
        let start = normalize(startAddress)
        let end = normalize(endAddress)
        guard !start.isEmpty, !end.isEmpty else { return nil }
        return "\(start)|\(end)"
    }

    private static func normalize(_ address: String) -> String {
        address
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
