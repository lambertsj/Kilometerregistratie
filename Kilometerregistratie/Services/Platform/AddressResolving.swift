import Foundation
import SwiftData

/// Zoekt een adres bij een coördinaat. Met een protocol kunnen tests zonder
/// netwerk draaien.
@MainActor
protocol AddressResolving {
    func address(latitude: Double, longitude: Double, context: ModelContext) async -> String?
}

extension GeocodingService: AddressResolving {}
