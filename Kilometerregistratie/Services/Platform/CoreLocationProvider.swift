import CoreLocation

/// Echte adapter: alleen doorgeven aan `CLLocationManager`, geen beslissingen.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    weak var delegate: LocationProvidingDelegate?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = true
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var locationServicesEnabled: Bool { CLLocationManager.locationServicesEnabled() }

    func requestWhenInUseAuthorization() { manager.requestWhenInUseAuthorization() }
    func requestAlwaysAuthorization() { manager.requestAlwaysAuthorization() }
    func startUpdatingLocation() { manager.startUpdatingLocation() }
    func stopUpdatingLocation() { manager.stopUpdatingLocation() }
    func startMonitoringSignificantLocationChanges() { manager.startMonitoringSignificantLocationChanges() }
    func stopMonitoringSignificantLocationChanges() { manager.stopMonitoringSignificantLocationChanges() }

    func apply(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) {
        manager.desiredAccuracy = accuracy
        manager.distanceFilter = distanceFilter
    }

    func setBackgroundUpdates(allowed: Bool, showsIndicator: Bool) {
        manager.allowsBackgroundLocationUpdates = allowed
        manager.showsBackgroundLocationIndicator = showsIndicator
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            delegate?.locationProviderDidChangeAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            delegate?.locationProvider(didUpdate: locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            delegate?.locationProviderDidFail(error)
        }
    }
}
