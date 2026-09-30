import Foundation
import SwiftData

/// Zet de SwiftData-inhoud om naar een BackupDocument en terug.
struct BackupService {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func createDocument() throws -> BackupDocument {
        let trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate)]))
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))
        let rules = try context.fetch(FetchDescriptor<ClassificationRule>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let revisions = try context.fetch(FetchDescriptor<TripRevision>(sortBy: [SortDescriptor(\.changedAt)]))

        return BackupDocument(
            formatVersion: 2,
            exportDate: .now,
            trips: trips.map { trip in
                BackupDocument.TripDTO(
                    id: trip.id,
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    startAddress: trip.startAddress,
                    endAddress: trip.endAddress,
                    startLatitude: trip.startLatitude,
                    startLongitude: trip.startLongitude,
                    endLatitude: trip.endLatitude,
                    endLongitude: trip.endLongitude,
                    distanceKm: trip.distanceKm,
                    startOdometer: trip.startOdometer,
                    endOdometer: trip.endOdometer,
                    category: trip.categoryRawValue,
                    note: trip.note,
                    clientLabel: trip.clientLabel,
                    isAutomaticallyRecorded: trip.isAutomaticallyRecorded,
                    routeData: trip.routeData,
                    vehicleID: trip.vehicle?.id,
                    destinationPlace: trip.destinationPlace,
                    destinationStreet: trip.destinationStreet,
                    purpose: trip.purpose,
                    businessPartner: trip.businessPartner,
                    detourNote: trip.detourNote,
                    deletedAt: trip.deletedAt
                )
            },
            vehicles: vehicles.map { vehicle in
                BackupDocument.VehicleDTO(
                    id: vehicle.id,
                    name: vehicle.name,
                    licensePlate: vehicle.licensePlate,
                    vehicleType: vehicle.vehicleType,
                    initialOdometer: vehicle.initialOdometer,
                    createdAt: vehicle.createdAt
                )
            },
            settings: settings.map { current in
                BackupDocument.SettingsDTO(
                    trackingMode: current.trackingModeRawValue,
                    reimbursementRatePerKm: current.reimbursementRatePerKm,
                    workHoursEnabled: current.workHoursEnabled,
                    workDayStartMinute: current.workDayStartMinute,
                    workDayEndMinute: current.workDayEndMinute,
                    workWeekdays: current.workWeekdays.sorted(),
                    autoStopThresholdMinutes: current.autoStopThresholdMinutes,
                    taxRegion: current.taxRegionRawValue
                )
            },
            classificationRules: rules.map {
                BackupDocument.RuleDTO(routeKey: $0.routeKey, category: $0.categoryRawValue, timesUsed: $0.timesUsed)
            },
            revisions: revisions.map { revision in
                BackupDocument.RevisionDTO(
                    id: revision.id,
                    tripID: revision.tripID,
                    changedAt: revision.changedAt,
                    tripStartDate: revision.tripStartDate,
                    changeKind: revision.changeKindRawValue,
                    field: revision.fieldRawValue,
                    previousValue: revision.previousValue,
                    newValue: revision.newValue,
                    wasContemporaneous: revision.wasContemporaneous
                )
            }
        )
    }

    /// Vervangt de volledige inhoud van de database door de back-up.
    ///
    /// Volgorde is bewust: eerst de nieuwe data invoegen en opslaan, pas
    /// daarna de oude verwijderen. Bij een fout halverwege (bv. schijf vol,
    /// een ongeldig record) blijft de bestaande data zo intact — hooguit
    /// tijdelijk gedupliceerd — in plaats van dat een mislukte restore de
    /// hele database al heeft leeggemaakt vóórdat er iets nieuws stond.
    func restore(from document: BackupDocument) throws {
        let oldTrips = try context.fetch(FetchDescriptor<Trip>())
        let oldVehicles = try context.fetch(FetchDescriptor<Vehicle>())
        let oldRules = try context.fetch(FetchDescriptor<ClassificationRule>())
        let oldSettings = try context.fetch(FetchDescriptor<AppSettings>())
        let oldRevisions = try context.fetch(FetchDescriptor<TripRevision>())

        var vehiclesByID: [UUID: Vehicle] = [:]
        for dto in document.vehicles {
            let vehicle = Vehicle(
                id: dto.id,
                name: dto.name,
                licensePlate: dto.licensePlate,
                vehicleType: dto.vehicleType,
                initialOdometer: dto.initialOdometer,
                createdAt: dto.createdAt
            )
            context.insert(vehicle)
            vehiclesByID[dto.id] = vehicle
        }

        for dto in document.trips {
            let trip = Trip(
                id: dto.id,
                startDate: dto.startDate,
                endDate: dto.endDate,
                startAddress: dto.startAddress,
                endAddress: dto.endAddress,
                startLatitude: dto.startLatitude,
                startLongitude: dto.startLongitude,
                endLatitude: dto.endLatitude,
                endLongitude: dto.endLongitude,
                distanceKm: dto.distanceKm,
                startOdometer: dto.startOdometer,
                endOdometer: dto.endOdometer,
                category: TripCategory(rawValue: dto.category) ?? .business,
                note: dto.note,
                clientLabel: dto.clientLabel,
                isAutomaticallyRecorded: dto.isAutomaticallyRecorded,
                routeData: dto.routeData,
                vehicle: dto.vehicleID.flatMap { vehiclesByID[$0] },
                destinationPlace: dto.destinationPlace,
                destinationStreet: dto.destinationStreet,
                purpose: dto.purpose,
                businessPartner: dto.businessPartner,
                detourNote: dto.detourNote,
                deletedAt: dto.deletedAt
            )
            context.insert(trip)
        }

        // Revisies gaan mee terug: een teruggezet dossier zonder
        // wijzigingsgeschiedenis zou zijn bewijswaarde verliezen.
        for dto in document.revisions {
            context.insert(TripRevision(
                id: dto.id,
                tripID: dto.tripID,
                changedAt: dto.changedAt,
                tripStartDate: dto.tripStartDate,
                changeKind: TripChangeKind(rawValue: dto.changeKind) ?? .updated,
                field: TripAuditField(rawValue: dto.field),
                previousValue: dto.previousValue,
                newValue: dto.newValue,
                wasContemporaneous: dto.wasContemporaneous
            ))
        }

        for dto in document.classificationRules {
            context.insert(ClassificationRule(
                routeKey: dto.routeKey,
                category: TripCategory(rawValue: dto.category) ?? .business,
                timesUsed: dto.timesUsed
            ))
        }

        if let dto = document.settings {
            let settings = AppSettings(
                trackingMode: TrackingMode(rawValue: dto.trackingMode) ?? .manual,
                reimbursementRatePerKm: dto.reimbursementRatePerKm,
                workHoursEnabled: dto.workHoursEnabled,
                workDayStartMinute: dto.workDayStartMinute,
                workDayEndMinute: dto.workDayEndMinute,
                workWeekdays: Set(dto.workWeekdays),
                autoStopThresholdMinutes: dto.autoStopThresholdMinutes,
                taxRegion: TaxRegion(rawValue: dto.taxRegion) ?? .netherlands
            )
            context.insert(settings)
        }

        try context.save()

        // Terugzetten vervangt het hele dossier door dat uit het bestand; de
        // oude records verdwijnen daarbij inclusief hun revisies. Dat is geen
        // stille wijziging van een bestaand dossier maar het vervangen ervan,
        // en het is een expliciete, door de gebruiker bevestigde actie.
        for trip in oldTrips { context.delete(trip) }
        for vehicle in oldVehicles { context.delete(vehicle) }
        for rule in oldRules { context.delete(rule) }
        for settings in oldSettings { context.delete(settings) }
        for revision in oldRevisions { context.delete(revision) }
        try context.save()
    }
}
