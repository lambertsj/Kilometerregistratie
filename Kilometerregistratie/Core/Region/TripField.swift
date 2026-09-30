import Foundation

/// De invulbare velden van een rit, als losse identiteiten zodat een regelset
/// per categorie kan zeggen wélke verplicht zijn. Nooit globaal verplicht:
/// de Nederlandse flow mag geen extra verplichte velden krijgen.
enum TripField: String, CaseIterable, Codable, Sendable {
    case date
    case distance
    case startOdometer
    case endOdometer
    case startAddress
    case endAddress

    /// Duitse Fahrtenbuch-velden (R 8.1 Abs. 9 Nr. 2 LStR).
    case destinationPlace
    case destinationStreet
    case purpose
    case businessPartner
    case detourNote
    /// Korte aantekening; volstaat voor woon-werkritten in Duitsland.
    case annotation
}
