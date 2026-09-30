import Foundation
import SwiftData

/// CRUD- en querylaag voor ritten. Views praten via deze repository met
/// SwiftData zodat query-logica op één plek staat en testbaar is met een
/// in-memory container.
struct TripRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - CRUD

    // Aanmaken, wijzigen en verwijderen lopen bewust *niet* via deze
    // repository maar via `TripWriteService`: dat is de enige plek waar de
    // audit trail geschreven wordt en dus de enige plek die mag schrijven.
    // Deze repository is er voor queries.

    func save() throws {
        try context.save()
    }

    // MARK: - Queries

    /// Ritten binnen een periode, optioneel gefilterd op categorie en/of
    /// voertuig, nieuwste eerst.
    func trips(
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        category: TripCategory? = nil,
        vehicleID: UUID? = nil
    ) throws -> [Trip] {
        let start = startDate ?? .distantPast
        let end = endDate ?? .distantFuture
        let categoryRaw = category?.rawValue

        // Verwijderde ritten (tombstones) horen nergens meer in thuis: niet in
        // lijsten, niet in totalen en niet in rapporten.
        let predicate = #Predicate<Trip> { trip in
            trip.deletedAt == nil
                && trip.startDate >= start && trip.startDate <= end
                && (categoryRaw == nil || trip.categoryRawValue == categoryRaw!)
        }
        var descriptor = FetchDescriptor<Trip>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.startDate, order: .reverse)]
        let fetched = try context.fetch(descriptor)

        // Relatie-filter na de fetch: optionele relaties in een #Predicate
        // zijn fragiel in SwiftData, en het aantal ritten per periode blijft
        // klein genoeg om dit in-memory te doen.
        guard let vehicleID else { return fetched }
        return fetched.filter { $0.vehicle?.id == vehicleID }
    }

    /// De rit die nu bezig is (gestart maar nog niet beëindigd), indien aanwezig.
    func activeTrip() throws -> Trip? {
        let predicate = #Predicate<Trip> { $0.endDate == nil && $0.deletedAt == nil }
        var descriptor = FetchDescriptor<Trip>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.startDate, order: .reverse)]
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// De meest recent afgesloten automatisch gedetecteerde rit, gebruikt om
    /// te beslissen of een nieuwe detectie hiermee samengevoegd moet worden
    /// (zie `AutomaticTripMerge`) in plaats van een aparte rit aan te maken.
    func mostRecentAutomaticTrip() throws -> Trip? {
        let predicate = #Predicate<Trip> { $0.isAutomaticallyRecorded && $0.endDate != nil && $0.deletedAt == nil }
        var descriptor = FetchDescriptor<Trip>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.endDate, order: .reverse)]
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Voegt `later` samen met `earlier` (bv. een kort onderbroken rit, of
    /// op verzoek van de gebruiker): `earlier` blijft staan met bijgewerkte
    /// eindgegevens en gecombineerde route/afstand; `later` verdwijnt.
    ///
    /// Beide mutaties lopen via `TripWriteService`, zodat het samenvoegen in
    /// een regio met bewaarplicht net zo goed in de audit trail terechtkomt
    /// als een handmatige wijziging — en de verdwijnende rit daar een
    /// tombstone wordt in plaats van echt weg te zijn.
    func merge(_ later: Trip, into earlier: Trip, using writer: TripWriteService) throws {
        let merged = TripMerge.merge(
            earlier: TripMerge.Input(
                startDate: earlier.startDate, endDate: earlier.endDate,
                startAddress: earlier.startAddress, endAddress: earlier.endAddress,
                distanceKm: earlier.distanceKm, note: earlier.note
            ),
            later: TripMerge.Input(
                startDate: later.startDate, endDate: later.endDate,
                startAddress: later.startAddress, endAddress: later.endAddress,
                distanceKm: later.distanceKm, note: later.note
            )
        )

        try writer.update(earlier) { trip in
            trip.endDate = merged.endDate
            trip.endAddress = merged.endAddress
            trip.distanceKm = merged.distanceKm
            trip.note = merged.note

            if let laterPoints = later.routeData.flatMap({ try? RoutePolyline.decode($0) }), !laterPoints.isEmpty {
                var points = trip.routeData.flatMap { try? RoutePolyline.decode($0) } ?? []
                let offsetBase = later.startDate.timeIntervalSince(trip.startDate)
                points.append(contentsOf: laterPoints.map {
                    RoutePoint(latitude: $0.latitude, longitude: $0.longitude, offset: $0.offset + offsetBase)
                })
                trip.routeData = try? RoutePolyline.encode(points)
            }
            if let endLatitude = later.endLatitude, let endLongitude = later.endLongitude {
                trip.endLatitude = endLatitude
                trip.endLongitude = endLongitude
            }
        }

        try writer.delete(later)
    }

    /// Lichtgewicht samenvattingen voor statistiek/dashboard.
    func summaries(
        from startDate: Date? = nil,
        to endDate: Date? = nil,
        vehicleID: UUID? = nil
    ) throws -> [TripSummary] {
        try trips(from: startDate, to: endDate, vehicleID: vehicleID).map {
            TripSummary(startDate: $0.startDate, distanceKm: $0.distanceKm, category: $0.category)
        }
    }
}
