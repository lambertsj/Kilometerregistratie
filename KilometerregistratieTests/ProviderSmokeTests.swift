import XCTest
@testable import Kilometerregistratie

/// De echte adapters bevatten geen logica en zijn bewust niet scenario-getest.
/// Deze rooktest bewaakt dat ze aan te maken en te sturen zijn.
@MainActor
final class ProviderSmokeTests: XCTestCase {
    func testCoreLocationProviderCanBeCreatedAndConfigured() {
        let provider = CoreLocationProvider()
        provider.apply(accuracy: 25, distanceFilter: 25)
        provider.startUpdatingLocation()
        provider.stopUpdatingLocation()
        provider.startMonitoringSignificantLocationChanges()
        provider.stopMonitoringSignificantLocationChanges()
        _ = provider.authorizationStatus
        _ = provider.locationServicesEnabled
    }

    func testCoreMotionProviderStartStopDoesNotCrash() {
        let provider = CoreMotionProvider()
        provider.start { _ in }
        provider.stop()
    }

    func testSystemTimeSourceFiresRepeatedlyAndCancels() async {
        let source = SystemTimeSource()
        var count = 0
        let handle = source.every(0.05) { count += 1 }
        try? await Task.sleep(for: .milliseconds(280))
        handle.cancel()
        let atCancel = count
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThanOrEqual(atCancel, 3)
        XCTAssertEqual(count, atCancel, "na cancel geen vuringen meer")
    }
}
