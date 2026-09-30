import Foundation
import SwiftData

/// Cache voor reverse-geocoding: veelgebruikte locaties (thuis, kantoor,
/// klanten) hoeven zo maar één keer via CLGeocoder opgezocht te worden.
@Model
final class CachedAddress {
    /// Coördinaten afgerond op ~100 m (3 decimalen) zodat dichtbij elkaar
    /// liggende GPS-fixes dezelfde cache-hit opleveren.
    var roundedLatitude: Double
    var roundedLongitude: Double
    var address: String
    var lastUsed: Date
    var useCount: Int

    init(roundedLatitude: Double, roundedLongitude: Double, address: String, lastUsed: Date = .now, useCount: Int = 1) {
        self.roundedLatitude = roundedLatitude
        self.roundedLongitude = roundedLongitude
        self.address = address
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    /// Rondt een coördinaat af op de cache-resolutie (3 decimalen ≈ 100 m).
    static func rounded(_ coordinate: Double) -> Double {
        (coordinate * 1000).rounded() / 1000
    }
}
