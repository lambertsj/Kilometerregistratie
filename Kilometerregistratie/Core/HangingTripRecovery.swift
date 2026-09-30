import Foundation

/// Beslist wat er moet gebeuren met een rit die nog "actief" (endDate == nil)
/// in de database staat wanneer de app opnieuw opstart — bv. omdat het
/// systeem de app tijdens een lopende rit heeft gekilld. Puur en UI-vrij zodat
/// dit los van CoreLocation/SwiftData getest kan worden.
enum HangingTripRecovery {
    enum Action: Equatable {
        /// De opname hervatten: recent genoeg dat we ervan uitgaan dat de rit
        /// nog bezig is.
        case resume
        /// De rit direct afsluiten op het laatst bekende moment: er is te
        /// veel tijd verstreken om aan te nemen dat de rit nog loopt, en
        /// doorgaan zou een groot "gat" onterecht als rijtijd meetellen.
        case finalize(endDate: Date)
    }

    /// Zoveel tijd mag er maximaal verstreken zijn sinds het laatst bekende
    /// teken van leven (laatste routepunt, of ritstart als er nog geen
    /// punten zijn) voordat we de rit niet meer hervatten maar afsluiten.
    static let maxGapBeforeFinalize: TimeInterval = 30 * 60

    static func decide(
        lastKnownActivity: Date,
        now: Date,
        maxGapBeforeFinalize: TimeInterval = maxGapBeforeFinalize
    ) -> Action {
        if now.timeIntervalSince(lastKnownActivity) >= maxGapBeforeFinalize {
            return .finalize(endDate: lastKnownActivity)
        }
        return .resume
    }
}
