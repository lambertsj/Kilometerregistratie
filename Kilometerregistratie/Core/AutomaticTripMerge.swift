import Foundation

/// Voorkomt dat een korte onderbreking in automatische detectie (bv. een
/// trein die kort op een station stopt en binnen enkele minuten weer
/// optrekt) een aparte nieuwe rit aanmaakt. Als er kort na het einde van de
/// vorige automatische rit alweer beweging wordt gedetecteerd, wordt de
/// vorige rit voortgezet in plaats van dat er een nieuwe rit ontstaat.
enum AutomaticTripMerge {
    /// Zoveel tijd mag er maximaal tussen het einde van de vorige
    /// automatische rit en het begin van de nieuwe zitten om ze nog als één
    /// rit te behandelen. Ruim boven de stilstand-drempel van `TripDetector`
    /// (die de rit al liet eindigen), maar kort genoeg om een écht nieuwe,
    /// losstaande rit niet abusievelijk samen te voegen.
    static let mergeWindow: TimeInterval = 5 * 60

    static func shouldMerge(previousTripEndDate: Date?, newTripStartDate: Date) -> Bool {
        guard let previousTripEndDate else { return false }
        return newTripStartDate.timeIntervalSince(previousTripEndDate) <= mergeWindow
    }
}
