import Foundation
import CoreLocation
import SwiftData

/// Reverse-geocoding met lokale cache: veelgebruikte plekken (thuis, kantoor,
/// klanten) worden na één keer opzoeken uit CachedAddress bediend, wat
/// geocoder-calls (en dus netwerk en batterij) bespaart.
struct GeocodingService {
    /// Adres voor een coördinaat, uit cache of via CLGeocoder.
    /// Geeft nil terug als geocoderen mislukt (bv. geen netwerk) — de rit
    /// blijft dan bruikbaar met alleen coördinaten.
    @MainActor
    func address(
        latitude: Double,
        longitude: Double,
        context: ModelContext
    ) async -> String? {
        let roundedLat = CachedAddress.rounded(latitude)
        let roundedLon = CachedAddress.rounded(longitude)

        let predicate = #Predicate<CachedAddress> {
            $0.roundedLatitude == roundedLat && $0.roundedLongitude == roundedLon
        }
        var descriptor = FetchDescriptor<CachedAddress>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let cached = try? context.fetch(descriptor).first {
            cached.lastUsed = .now
            cached.useCount += 1
            try? context.save()
            return cached.address
        }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        let address = Self.formatAddress(from: placemark)
        guard !address.isEmpty else { return nil }

        context.insert(CachedAddress(roundedLatitude: roundedLat, roundedLongitude: roundedLon, address: address))
        try? context.save()
        return address
    }

    /// Compact NL-formaat: "Straat 12, Plaats".
    static func formatAddress(from placemark: CLPlacemark) -> String {
        var street = placemark.thoroughfare ?? ""
        if let number = placemark.subThoroughfare, !number.isEmpty {
            street = street.isEmpty ? number : "\(street) \(number)"
        }
        let city = placemark.locality ?? placemark.subLocality ?? ""
        switch (street.isEmpty, city.isEmpty) {
        case (false, false): return "\(street), \(city)"
        case (false, true): return street
        case (true, false): return city
        case (true, true): return placemark.name ?? ""
        }
    }
}
