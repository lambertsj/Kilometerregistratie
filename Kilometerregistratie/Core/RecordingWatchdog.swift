import Foundation

/// Bewaakt een lopende rit-opname onafhankelijk van binnenkomende
/// locatie-samples. `TripDetector` kan een rit alleen beëindigen als er nog
/// samples binnenkomen; zodra iOS de GPS volledig pauzeert (of de app geen
/// updates meer krijgt) blijft een rit anders voor altijd "actief" staan.
/// Deze pure, UI-vrije klok wordt periodiek aangeroepen (los van CoreLocation)
/// zodat een rit hoe dan ook netjes wordt afgesloten.
struct RecordingWatchdog: Equatable {
    /// Zelfde drempel als de stilstand-detectie in `TripDetector`, plus een
    /// marge: als er langer dan dit géén sample is binnengekomen, is er iets
    /// mis met de GPS-stroom zelf (iOS heeft updates gepauzeerd, tunnel,
    /// achtergrondlimiet) en moet de rit alsnog stoppen.
    var stopAfterStationaryInterval: TimeInterval
    /// Absolute bovengrens op de duur van één rit, ongeacht samples: voorkomt
    /// dat een kapotte sensor of een oneindige lage-snelheid-lus een rit
    /// uren of dagen laat doorlopen.
    var maxTripDuration: TimeInterval

    static let gpsSilenceGrace: TimeInterval = 60

    init(stopAfterStationaryInterval: TimeInterval, maxTripDuration: TimeInterval = 16 * 3600) {
        self.stopAfterStationaryInterval = stopAfterStationaryInterval
        self.maxTripDuration = maxTripDuration
    }

    /// True als de opname nu geforceerd afgesloten moet worden.
    func shouldForceStop(recordingStartedAt: Date, lastSampleAt: Date, now: Date) -> Bool {
        if now.timeIntervalSince(lastSampleAt) >= stopAfterStationaryInterval + Self.gpsSilenceGrace {
            return true
        }
        if now.timeIntervalSince(recordingStartedAt) >= maxTripDuration {
            return true
        }
        return false
    }
}
