import Foundation
import SwiftData

/// Het schema zoals het in versie 1.0 van de app op de toestellen staat.
///
/// De modellen staan hier bewust opnieuw en volledig uitgeschreven, en niet
/// als verwijzing naar de huidige klassen. Alleen zo kan de migratietest een
/// database in de *oude* vorm aanmaken en aantonen dat er bij het migreren
/// niets verloren gaat. De klassenamen binnen deze enum zijn gelijk aan die
/// van nu, zodat SwiftData dezelfde entiteiten herkent.
///
/// Dit bestand is een historisch document: pas het niet aan als het schema
/// verandert — voeg dan een nieuwe versie toe.
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, Vehicle.self, AppSettings.self, CachedAddress.self, ClassificationRule.self]
    }

    @Model
    final class Trip {
        var id: UUID = UUID()
        var startDate: Date = Date.distantPast
        var endDate: Date?
        var startAddress: String = ""
        var endAddress: String = ""
        var startLatitude: Double?
        var startLongitude: Double?
        var endLatitude: Double?
        var endLongitude: Double?
        var distanceKm: Double = 0
        var startOdometer: Double?
        var endOdometer: Double?
        var categoryRawValue: String = "zakelijk"
        var note: String = ""
        var clientLabel: String = ""
        var isAutomaticallyRecorded: Bool = false
        var routeData: Data?
        var vehicle: Vehicle?

        init(
            id: UUID = UUID(),
            startDate: Date,
            endDate: Date? = nil,
            startAddress: String = "",
            endAddress: String = "",
            startLatitude: Double? = nil,
            startLongitude: Double? = nil,
            endLatitude: Double? = nil,
            endLongitude: Double? = nil,
            distanceKm: Double = 0,
            startOdometer: Double? = nil,
            endOdometer: Double? = nil,
            categoryRawValue: String = "zakelijk",
            note: String = "",
            clientLabel: String = "",
            isAutomaticallyRecorded: Bool = false,
            routeData: Data? = nil,
            vehicle: Vehicle? = nil
        ) {
            self.id = id
            self.startDate = startDate
            self.endDate = endDate
            self.startAddress = startAddress
            self.endAddress = endAddress
            self.startLatitude = startLatitude
            self.startLongitude = startLongitude
            self.endLatitude = endLatitude
            self.endLongitude = endLongitude
            self.distanceKm = distanceKm
            self.startOdometer = startOdometer
            self.endOdometer = endOdometer
            self.categoryRawValue = categoryRawValue
            self.note = note
            self.clientLabel = clientLabel
            self.isAutomaticallyRecorded = isAutomaticallyRecorded
            self.routeData = routeData
            self.vehicle = vehicle
        }
    }

    @Model
    final class Vehicle {
        var id: UUID = UUID()
        var name: String = ""
        var licensePlate: String = ""
        var vehicleType: String = "Auto"
        var initialOdometer: Double = 0
        var createdAt: Date = Date.distantPast

        @Relationship(deleteRule: .nullify, inverse: \Trip.vehicle)
        var trips: [Trip] = []

        init(
            id: UUID = UUID(),
            name: String,
            licensePlate: String = "",
            vehicleType: String = "Auto",
            initialOdometer: Double = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.licensePlate = licensePlate
            self.vehicleType = vehicleType
            self.initialOdometer = initialOdometer
            self.createdAt = createdAt
        }
    }

    @Model
    final class AppSettings {
        var trackingModeRawValue: String = "handmatig"
        var reimbursementRatePerKm: Double = 0.23
        var workHoursEnabled: Bool = false
        var workDayStartMinute: Int = 9 * 60
        var workDayEndMinute: Int = 17 * 60
        var workWeekdaysRawValue: String = "2,3,4,5,6"
        var autoStopThresholdMinutes: Int = 3
        var iCloudBackupEnabled: Bool = false
        var locationAccuracyRawValue: String = "gebalanceerd"

        init(
            trackingModeRawValue: String = "handmatig",
            reimbursementRatePerKm: Double = 0.23,
            workHoursEnabled: Bool = false,
            workDayStartMinute: Int = 9 * 60,
            workDayEndMinute: Int = 17 * 60,
            workWeekdaysRawValue: String = "2,3,4,5,6",
            autoStopThresholdMinutes: Int = 3,
            iCloudBackupEnabled: Bool = false,
            locationAccuracyRawValue: String = "gebalanceerd"
        ) {
            self.trackingModeRawValue = trackingModeRawValue
            self.reimbursementRatePerKm = reimbursementRatePerKm
            self.workHoursEnabled = workHoursEnabled
            self.workDayStartMinute = workDayStartMinute
            self.workDayEndMinute = workDayEndMinute
            self.workWeekdaysRawValue = workWeekdaysRawValue
            self.autoStopThresholdMinutes = autoStopThresholdMinutes
            self.iCloudBackupEnabled = iCloudBackupEnabled
            self.locationAccuracyRawValue = locationAccuracyRawValue
        }
    }

    @Model
    final class CachedAddress {
        var roundedLatitude: Double = 0
        var roundedLongitude: Double = 0
        var address: String = ""
        var lastUsed: Date = Date.distantPast
        var useCount: Int = 1

        init(roundedLatitude: Double, roundedLongitude: Double, address: String, lastUsed: Date = .now, useCount: Int = 1) {
            self.roundedLatitude = roundedLatitude
            self.roundedLongitude = roundedLongitude
            self.address = address
            self.lastUsed = lastUsed
            self.useCount = useCount
        }
    }

    @Model
    final class ClassificationRule {
        var routeKey: String = ""
        var categoryRawValue: String = "zakelijk"
        var timesUsed: Int = 1
        var updatedAt: Date = Date.distantPast

        init(routeKey: String, categoryRawValue: String, timesUsed: Int = 1, updatedAt: Date = .now) {
            self.routeKey = routeKey
            self.categoryRawValue = categoryRawValue
            self.timesUsed = timesUsed
            self.updatedAt = updatedAt
        }
    }
}
