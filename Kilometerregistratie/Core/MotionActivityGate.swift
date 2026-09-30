import Foundation

/// Beslist of een locatiesample een automatische rit mag starten, op basis
/// van CoreMotion-activiteit naast de snelheidsdrempel in `TripDetector`.
/// Voorkomt dat OV of fietsen een rit triggert wanneer toevallig de
/// snelheidsdrempel gehaald wordt (een trein trekt net zo hard op als een
/// auto). Puur en CoreMotion-vrij zodat dit los van `CMMotionActivityManager`
/// getest kan worden.
enum MotionActivityGate {
    struct ActivitySample: Equatable {
        var automotive: Bool
        var confidence: Confidence

        enum Confidence: Int, Equatable, Comparable {
            case low, medium, high
            static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
        }
    }

    /// True als de gegeven activiteit een automatische ritstart toestaat.
    /// Zonder recent sample (CoreMotion niet beschikbaar, toestemming
    /// geweigerd, of nog geen classificatie) valt de beslissing terug op
    /// snelheid alleen, zodat automatische detectie niet blokkeert wanneer
    /// CoreMotion er simpelweg geen mening over heeft. Bij lage confidence
    /// is CoreMotion zelf onzeker, dus laten we die net zo min blokkeren.
    static func allowsAutomaticStart(_ activity: ActivitySample?) -> Bool {
        guard let activity else { return true }
        if activity.confidence == .low { return true }
        return activity.automotive
    }
}
