import Foundation

/// Combineert de fiscale velden van twee opeenvolgende ritten tot één, voor
/// zowel de automatische samenvoeg-cooldown als de handmatige "voeg samen
/// met vorige rit"-actie. Puur en UI/SwiftData-vrij zodat de veldregels
/// (wie "wint") los getest kunnen worden.
enum TripMerge {
    struct Input: Equatable {
        var startDate: Date
        var endDate: Date?
        var startAddress: String
        var endAddress: String
        var distanceKm: Double
        var note: String
    }

    /// `earlier` blijft leidend voor start; `later` levert het eindpunt.
    /// Afstand wordt opgeteld, notities worden samengevoegd als ze
    /// verschillen.
    static func merge(earlier: Input, later: Input) -> Input {
        Input(
            startDate: earlier.startDate,
            endDate: later.endDate ?? earlier.endDate,
            startAddress: earlier.startAddress,
            endAddress: later.endAddress.isEmpty ? earlier.endAddress : later.endAddress,
            distanceKm: earlier.distanceKm + later.distanceKm,
            note: mergedNote(earlier.note, later.note)
        )
    }

    private static func mergedNote(_ earlier: String, _ later: String) -> String {
        let parts = [earlier, later].filter { !$0.isEmpty }
        if parts.count == 2, parts[0] == parts[1] { return parts[0] }
        return parts.joined(separator: " / ")
    }
}
