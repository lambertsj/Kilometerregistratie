import Foundation

/// Pure afstandsberekening, bewust zonder CoreLocation-dependency zodat dit
/// overal (ook in een command-line testharness) compileert en testbaar is.
enum GeoDistance {
    private static let earthRadiusMeters = 6_371_000.0

    /// Haversine-afstand in meters tussen twee coördinaten.
    static func meters(
        fromLatitude lat1: Double, longitude lon1: Double,
        toLatitude lat2: Double, longitude lon2: Double
    ) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let deltaPhi = (lat2 - lat1) * .pi / 180
        let deltaLambda = (lon2 - lon1) * .pi / 180

        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2)
            + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    /// Totale lengte van een opgenomen route in kilometers.
    static func routeDistanceKm(_ points: [RoutePoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var totalMeters = 0.0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            totalMeters += meters(
                fromLatitude: previous.latitude, longitude: previous.longitude,
                toLatitude: current.latitude, longitude: current.longitude
            )
        }
        return totalMeters / 1000
    }
}
