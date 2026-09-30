import Foundation
import CoreLocation
import MapKit

/// Berekent de rijafstand tussen twee adressen. Achter een protocol zodat
/// views testbaar blijven zonder netwerk/MapKit.
protocol RouteDistanceProviding: Sendable {
    func distanceKm(fromAddress: String, toAddress: String) async throws -> Double
}

enum RouteDistanceError: LocalizedError {
    case addressNotFound(String)
    case noRouteFound

    var errorDescription: String? {
        switch self {
        case .addressNotFound(let address):
            "Adres niet gevonden: \(address)"
        case .noRouteFound:
            "Geen route gevonden tussen deze adressen."
        }
    }
}

/// MapKit-implementatie: geocodeert beide adressen en vraagt één autoroute
/// op. Dit is het enige netwerkverkeer in de app naast optionele iCloud;
/// er gaan alleen de twee ingevoerde adressen naar Apple's geocoder.
struct MapKitRouteDistanceService: RouteDistanceProviding {
    func distanceKm(fromAddress: String, toAddress: String) async throws -> Double {
        let from = try await geocode(fromAddress)
        let to = try await geocode(toAddress)

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw RouteDistanceError.noRouteFound
        }
        return route.distance / 1000
    }

    private func geocode(_ address: String) async throws -> CLLocationCoordinate2D {
        let placemarks = try await CLGeocoder().geocodeAddressString(address)
        guard let coordinate = placemarks.first?.location?.coordinate else {
            throw RouteDistanceError.addressNotFound(address)
        }
        return coordinate
    }
}
