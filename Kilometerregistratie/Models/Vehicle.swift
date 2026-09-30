import Foundation
import SwiftData

/// Een voertuig waarmee ritten worden gereden.
@Model
final class Vehicle {
    var id: UUID
    var name: String
    var licensePlate: String
    /// Vrij tekstveld: "Auto", "Motor", "Bestelbus", …
    var vehicleType: String
    /// Kilometerstand op het moment dat registratie in de app begon.
    var initialOdometer: Double
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Trip.vehicle)
    var trips: [Trip] = []

    init(
        id: UUID = UUID(),
        name: String,
        licensePlate: String = "",
        vehicleType: String = "Auto",
        initialOdometer: Double = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.licensePlate = licensePlate
        self.vehicleType = vehicleType
        self.initialOdometer = initialOdometer
        self.createdAt = createdAt
    }
}
