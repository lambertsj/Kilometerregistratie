import Foundation

/// Filtert losse GPS-samples voordat ze aan de opgenomen route worden
/// toegevoegd: verwerpt te onnauwkeurige metingen én fysiek onmogelijke
/// sprongen (bv. een GPS-glitch die het toestel honderden meters laat
/// "springen" binnen een fractie van een seconde, zoals in een tunnel of
/// parkeergarage kan gebeuren). Puur en CoreLocation-vrij zodat dit los
/// getest kan worden.
enum GPSPointFilter {
    struct Sample {
        var latitude: Double
        var longitude: Double
        var horizontalAccuracy: Double
        var timestamp: Date
    }

    /// Standaarddrempel voor de onzekerheidsradius; op een ruimere marge
    /// (bv. de eerder gebruikte 100 m) kan één slecht sample de afstand van
    /// een korte rit al flink vertekenen. `LocationTrackingService` gebruikt
    /// een ruimere drempel in de batterijbesparende stand, waar
    /// `desiredAccuracy` zelf al grover staat.
    static let defaultMaxHorizontalAccuracy: Double = 50
    /// Ruim boven de snelste realistische wegsnelheid, zodat legitiem hard
    /// rijden nooit wordt verworpen — enkel evidente GPS-sprongen.
    static let maxPlausibleSpeed: Double = 60 // m/s, ≈ 216 km/h

    /// True als het sample aan de route toegevoegd mag worden. `previous` is
    /// het laatst geaccepteerde sample (niet per se het vorige binnengekomen
    /// sample, want verworpen samples tellen niet mee als referentiepunt).
    static func accepts(
        _ sample: Sample,
        previous: Sample?,
        maxHorizontalAccuracy: Double = defaultMaxHorizontalAccuracy
    ) -> Bool {
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= maxHorizontalAccuracy else { return false }
        guard let previous else { return true }

        let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return false }

        let distance = GeoDistance.meters(
            fromLatitude: previous.latitude, longitude: previous.longitude,
            toLatitude: sample.latitude, longitude: sample.longitude
        )
        return distance / elapsed <= maxPlausibleSpeed
    }
}
