import Foundation
import SwiftData

/// Beheert de handmatige START/STOP-registratie. De actieve rit leeft alleen
/// in de database (endDate == nil) en wordt telkens via
/// `TripRepository.activeTrip()` opgehaald. Zo ziet STOP ook een rit die de
/// automatische detectie op de achtergrond heeft gestart, en blijft een
/// lopende rit een app-herstart overleven.
@MainActor
struct TripRecorder {
    /// Tijd van START/STOP; scenario-tests geven een virtuele klok mee.
    var now: () -> Date = { .now }

    /// Start een handmatige rit, tenzij er al een actieve rit is (handmatig
    /// of automatisch). Geeft de nieuwe rit terug, of nil als er niets
    /// gestart is.
    @discardableResult
    func start(context: ModelContext, vehicle: Vehicle?) throws -> Trip? {
        guard try TripRepository(context: context).activeTrip() == nil else { return nil }
        let trip = Trip(startDate: now(), vehicle: vehicle)
        try TripWriteService(context: context).create(trip)
        return trip
    }

    /// Beëindigt de lopende rit en geeft hem terug zodat de UI het
    /// afrondformulier (afstand, adressen, categorie) kan tonen.
    @discardableResult
    func stop(context: ModelContext) throws -> Trip? {
        guard let trip = try TripRepository(context: context).activeTrip() else { return nil }
        // De rit is hier nog niet afgesloten, dus dit telt als het opbouwen
        // van de registratie en niet als een wijziging achteraf.
        let end = now()
        try TripWriteService(context: context).update(trip) { $0.endDate = end }
        return trip
    }

    /// Annuleert de lopende rit en verwijdert hem (bv. per ongeluk gestart).
    func cancel(context: ModelContext) throws {
        guard let trip = try TripRepository(context: context).activeTrip() else { return }
        try TripWriteService(context: context).delete(trip)
    }
}
