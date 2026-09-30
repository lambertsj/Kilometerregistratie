import Foundation
import SwiftData

/// CRUD-laag voor voertuigen.
struct VehicleRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func add(_ vehicle: Vehicle) throws {
        context.insert(vehicle)
        try context.save()
    }

    /// Reden waarom een voertuig niet verwijderd kan worden.
    enum DeletionRefusal: LocalizedError {
        case hasTripsAndRegionRequiresAuditTrail(tripCount: Int)

        var errorDescription: String? {
            switch self {
            case .hasTripsAndRegionRequiresAuditTrail(let tripCount):
                let template = String(localized: "Dit voertuig heeft %@ geregistreerde rit(ten). In de ingestelde regio moet de kilometerreeks per voertuig sluitend blijven, daarom kan het voertuig niet verwijderd worden.", comment: "Foutmelding: voertuig met ritten kan niet verwijderd worden in een regio met bewaarplicht; %@ is het aantal ritten")
                return String(format: template, tripsCountText(tripCount))
            }
        }
    }

    /// Verwijdert een voertuig; gekoppelde ritten blijven bestaan
    /// (deleteRule .nullify) zodat de administratie sluitend blijft.
    ///
    /// In een regio met bewaarplicht kan dat niet: `.nullify` maakt de ritten
    /// voertuigloos en breekt daarmee juist de sluitende kilometerreeks per
    /// voertuig. Verwijderen wordt dan geweigerd, met opgaaf van reden.
    func delete(_ vehicle: Vehicle, ruleSet: any RegionRuleSet) throws {
        if ruleSet.requiresAuditTrail, !vehicle.trips.isEmpty {
            throw DeletionRefusal.hasTripsAndRegionRequiresAuditTrail(tripCount: vehicle.trips.count)
        }
        context.delete(vehicle)
        try context.save()
    }

    func allVehicles() throws -> [Vehicle] {
        var descriptor = FetchDescriptor<Vehicle>()
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try context.fetch(descriptor)
    }

    /// Geschatte actuele kilometerstand: beginstand + alle geregistreerde
    /// kilometers van dit voertuig.
    func estimatedOdometer(for vehicle: Vehicle) -> Double {
        vehicle.initialOdometer + vehicle.trips.reduce(0) { $0 + $1.distanceKm }
    }
}
