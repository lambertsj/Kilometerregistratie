import CoreLocation
@testable import Kilometerregistratie

/// Nagebootste locatiebron: legt elke aanroep vast en levert alleen locaties
/// af als een test dat zegt. De regels waaronder iOS dat zou doen zitten in
/// `FakeIOS`.
@MainActor
final class FakeLocationProvider: LocationProviding {
    weak var delegate: LocationProvidingDelegate?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var locationServicesEnabled = true

    private(set) var isUpdating = false
    private(set) var isMonitoringSignificantChanges = false
    private(set) var distanceFilter: CLLocationDistance = 25
    private(set) var backgroundAllowed = false
    private(set) var calls: [String] = []

    func requestWhenInUseAuthorization() { calls.append("requestWhenInUse") }
    func requestAlwaysAuthorization() { calls.append("requestAlways") }
    func startUpdatingLocation() { isUpdating = true; calls.append("startUpdating") }
    func stopUpdatingLocation() { isUpdating = false; calls.append("stopUpdating") }
    func startMonitoringSignificantLocationChanges() { isMonitoringSignificantChanges = true; calls.append("startSignificant") }
    func stopMonitoringSignificantLocationChanges() { isMonitoringSignificantChanges = false; calls.append("stopSignificant") }
    func apply(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) {
        self.distanceFilter = distanceFilter
        calls.append("apply(\(distanceFilter))")
    }
    func setBackgroundUpdates(allowed: Bool, showsIndicator: Bool) { backgroundAllowed = allowed }

    /// Levert locaties af zoals CoreLocation dat doet.
    func deliver(_ locations: [CLLocation]) {
        delegate?.locationProvider(didUpdate: locations)
    }

    /// Wijzigt de toestemming en meldt dat zoals iOS dat doet.
    func changeAuthorization(to status: CLAuthorizationStatus) {
        authorizationStatus = status
        delegate?.locationProviderDidChangeAuthorization()
    }

    /// Een nieuw proces start zonder lopende updates; alleen het
    /// significante-wijzigingen-abonnement blijft bij het systeem staan.
    func resetForNewProcess() {
        isUpdating = false
        backgroundAllowed = false
        delegate = nil
    }
}
