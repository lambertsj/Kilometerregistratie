import Foundation
import SwiftData
import Observation

/// Beheert de handmatige START/STOP-registratie. De actieve rit wordt
/// direct gepersisteerd (endDate == nil) zodat een lopende rit een
/// app-herstart overleeft en via `TripRepository.activeTrip()` terugkomt.
@Observable
@MainActor
final class TripRecorder {
    private(set) var activeTrip: Trip?

    /// Herstelt een eventueel nog lopende rit uit de database (na herstart).
    func restoreActiveTrip(context: ModelContext) {
        activeTrip = try? TripRepository(context: context).activeTrip()
    }

    func start(context: ModelContext, vehicle: Vehicle?) throws {
        guard activeTrip == nil else { return }
        let trip = Trip(startDate: .now, vehicle: vehicle)
        try TripWriteService(context: context).create(trip)
        activeTrip = trip
    }

    /// Beëindigt de lopende rit en geeft hem terug zodat de UI het
    /// afrondformulier (afstand, adressen, categorie) kan tonen.
    @discardableResult
    func stop(context: ModelContext) throws -> Trip? {
        guard let trip = activeTrip else { return nil }
        // De rit is hier nog niet afgesloten, dus dit telt als het opbouwen
        // van de registratie en niet als een wijziging achteraf.
        try TripWriteService(context: context).update(trip) { $0.endDate = .now }
        activeTrip = nil
        return trip
    }

    /// Annuleert de lopende rit en verwijdert hem (bv. per ongeluk gestart).
    func cancel(context: ModelContext) throws {
        guard let trip = activeTrip else { return }
        try TripWriteService(context: context).delete(trip)
        activeTrip = nil
    }
}
