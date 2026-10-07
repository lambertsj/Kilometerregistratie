import CoreLocation

@MainActor
protocol LocationProvidingDelegate: AnyObject {
    func locationProvider(didUpdate locations: [CLLocation])
    func locationProviderDidChangeAuthorization()
    func locationProviderDidFail(_ error: Error)
}

/// Dunne laag om `CLLocationManager`, zodat de service zonder CoreLocation
/// getest kan worden. Bevat bewust geen logica.
@MainActor
protocol LocationProviding: AnyObject {
    var delegate: LocationProvidingDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    var locationServicesEnabled: Bool { get }

    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
    func apply(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance)
    func setBackgroundUpdates(allowed: Bool, showsIndicator: Bool)
}
