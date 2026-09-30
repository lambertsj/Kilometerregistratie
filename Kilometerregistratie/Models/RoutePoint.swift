import Foundation

/// Eén punt van een opgenomen route. Compact en Codable zodat een hele
/// route als één Data-blob in SwiftData past in plaats van duizenden rijen.
struct RoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Seconden sinds de start van de rit (compacter dan een volledige Date).
    var offset: TimeInterval
}

enum RoutePolyline {
    static func encode(_ points: [RoutePoint]) throws -> Data {
        try JSONEncoder().encode(points)
    }

    static func decode(_ data: Data) throws -> [RoutePoint] {
        try JSONDecoder().decode([RoutePoint].self, from: data)
    }
}
