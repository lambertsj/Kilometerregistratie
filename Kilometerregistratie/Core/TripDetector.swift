import Foundation

/// Pure toestandsmachine voor automatische ritdetectie. Krijgt locatie-
/// samples (snelheid + tijd) en beslist wanneer een rit begint en eindigt.
/// Bewust los van CoreLocation zodat dit volledig unit-testbaar is.
struct TripDetector {
    struct Sample {
        var latitude: Double
        var longitude: Double
        /// Snelheid in m/s; negatief betekent onbekend (zoals CLLocation.speed).
        var speed: Double
        var timestamp: Date

        init(latitude: Double, longitude: Double, speed: Double, timestamp: Date) {
            self.latitude = latitude
            self.longitude = longitude
            self.speed = speed
            self.timestamp = timestamp
        }
    }

    enum Event: Equatable {
        case none
        /// Rijden gedetecteerd: rit begint bij dit sample.
        case tripStarted
        /// Langdurige stilstand: rit eindigt op `lastMovementDate`.
        case tripEnded(endDate: Date)
    }

    enum State: Equatable {
        case idle
        case moving
    }

    /// Vanaf ~20 km/u beschouwen we het als rijden (fietsers/wandelaars
    /// halen dit zelden structureel; drempel voorkomt valse starts).
    var startSpeedThreshold: Double = 5.5
    /// Onder ~5 km/u telt als stilstand (file kruipt hier meestal boven).
    var stationarySpeedThreshold: Double = 1.4
    /// Zoveel seconden aaneengesloten stilstand beëindigt de rit.
    var stopAfterStationaryInterval: TimeInterval

    private(set) var state: State = .idle
    /// Laatste moment waarop beweging is gezien tijdens een rit.
    private(set) var lastMovementDate: Date?

    init(stopAfterStationaryInterval: TimeInterval = 180) {
        self.stopAfterStationaryInterval = stopAfterStationaryInterval
    }

    mutating func process(_ sample: Sample) -> Event {
        switch state {
        case .idle:
            if sample.speed >= startSpeedThreshold {
                state = .moving
                lastMovementDate = sample.timestamp
                return .tripStarted
            }
            return .none

        case .moving:
            if sample.speed >= stationarySpeedThreshold {
                lastMovementDate = sample.timestamp
                return .none
            }
            // Stilstand: rit eindigt pas na de ingestelde drempel, zodat
            // stoplichten en korte stops de rit niet opknippen.
            let lastMovement = lastMovementDate ?? sample.timestamp
            if sample.timestamp.timeIntervalSince(lastMovement) >= stopAfterStationaryInterval {
                state = .idle
                let endDate = lastMovement
                lastMovementDate = nil
                return .tripEnded(endDate: endDate)
            }
            return .none
        }
    }

    /// Forceert terug naar idle (bv. wanneer tracking uitgezet wordt).
    mutating func reset() {
        state = .idle
        lastMovementDate = nil
    }
}
