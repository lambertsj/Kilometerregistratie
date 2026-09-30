import Foundation
import SwiftData

/// Bewijst dat de migratie van schema 1 naar 2 geen data kost.
///
/// De aanpak is bewust niet "maak een lege database aan en kijk of hij opent",
/// maar: vul een database in de *oude* vorm (`AppSchemaV1`), sluit hem, open
/// hem opnieuw met het huidige schema plus migratieplan, en vergelijk elk veld
/// van elke rit met wat erin ging.
enum MigrationTests {
    /// Een tijdelijke database op schijf; in-memory kan niet, want dan valt er
    /// niets te migreren.
    private static func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("km-migration-\(UUID().uuidString).store")
    }

    private struct ExpectedTrip {
        var id: UUID
        var startDate: Date
        var endDate: Date?
        var startAddress: String
        var endAddress: String
        var startLatitude: Double?
        var startLongitude: Double?
        var endLatitude: Double?
        var endLongitude: Double?
        var distanceKm: Double
        var startOdometer: Double?
        var endOdometer: Double?
        var categoryRawValue: String
        var note: String
        var clientLabel: String
        var isAutomaticallyRecorded: Bool
        var routeData: Data?
        var vehicleName: String?
    }

    static func run() {
        Harness.suite("Migratie V1 → V2: geen dataverlies") {
            let url = temporaryStoreURL()
            defer { try? FileManager.default.removeItem(at: url) }

            let route = try RoutePolyline.encode([
                RoutePoint(latitude: 52.37, longitude: 4.89, offset: 0),
                RoutePoint(latitude: 52.09, longitude: 5.12, offset: 1800),
            ])

            var expected: [ExpectedTrip] = []

            // ── Stap 1: een database in de oude vorm vullen ──────────────
            do {
                let schema = Schema(versionedSchema: AppSchemaV1.self)
                let configuration = ModelConfiguration(schema: schema, url: url)
                let container = try ModelContainer(for: schema, configurations: configuration)
                let context = ModelContext(container)

                let vehicle = AppSchemaV1.Vehicle(
                    name: "Bedrijfsauto", licensePlate: "XX-123-Y",
                    vehicleType: "Auto", initialOdometer: 34_180,
                    createdAt: Fixtures.date(2025, 1, 1)
                )
                context.insert(vehicle)

                // Een volledig gevulde rit, een minimale rit, en een rit die
                // nog liep — de drie vormen die in de praktijk voorkomen.
                let full = AppSchemaV1.Trip(
                    startDate: Fixtures.date(2026, 3, 2, 8, 15),
                    endDate: Fixtures.date(2026, 3, 2, 9, 5),
                    startAddress: "Thuisstraat 1", endAddress: "Kantoorlaan 5",
                    startLatitude: 52.37, startLongitude: 4.89,
                    endLatitude: 52.09, endLongitude: 5.12,
                    distanceKm: 30, startOdometer: 50_000, endOdometer: 50_030,
                    categoryRawValue: "zakelijk", note: "Klantbezoek",
                    clientLabel: "Jansen BV", isAutomaticallyRecorded: true,
                    routeData: route, vehicle: vehicle
                )
                let minimal = AppSchemaV1.Trip(
                    startDate: Fixtures.date(2026, 3, 3, 19, 40),
                    distanceKm: 12.5, categoryRawValue: "privé"
                )
                let running = AppSchemaV1.Trip(
                    startDate: Fixtures.date(2026, 3, 4, 7, 50),
                    endDate: nil, startAddress: "Thuisstraat 1",
                    distanceKm: 7.5, categoryRawValue: "woon-werk",
                    vehicle: vehicle
                )
                for trip in [full, minimal, running] { context.insert(trip) }

                let settings = AppSchemaV1.AppSettings(
                    trackingModeRawValue: "hybride",
                    reimbursementRatePerKm: 0.19,
                    workHoursEnabled: true,
                    workWeekdaysRawValue: "2,3,4"
                )
                context.insert(settings)
                context.insert(AppSchemaV1.ClassificationRule(
                    routeKey: "thuisstraat 1|kantoorlaan 5", categoryRawValue: "zakelijk", timesUsed: 4
                ))
                context.insert(AppSchemaV1.CachedAddress(
                    roundedLatitude: 52.37, roundedLongitude: 4.89, address: "Thuisstraat 1"
                ))
                try context.save()

                for trip in [full, minimal, running] {
                    expected.append(ExpectedTrip(
                        id: trip.id, startDate: trip.startDate, endDate: trip.endDate,
                        startAddress: trip.startAddress, endAddress: trip.endAddress,
                        startLatitude: trip.startLatitude, startLongitude: trip.startLongitude,
                        endLatitude: trip.endLatitude, endLongitude: trip.endLongitude,
                        distanceKm: trip.distanceKm, startOdometer: trip.startOdometer,
                        endOdometer: trip.endOdometer, categoryRawValue: trip.categoryRawValue,
                        note: trip.note, clientLabel: trip.clientLabel,
                        isAutomaticallyRecorded: trip.isAutomaticallyRecorded,
                        routeData: trip.routeData, vehicleName: trip.vehicle?.name
                    ))
                }
            }

            // ── Stap 2: opnieuw openen met het huidige schema ────────────
            let configuration = ModelConfiguration(schema: AppSchema.schema, url: url)
            let container = try ModelContainer(
                for: AppSchema.schema,
                migrationPlan: AppSchema.migrationPlan,
                configurations: configuration
            )
            let context = ModelContext(container)

            // ── Stap 3: alles terugvergelijken ──────────────────────────
            let migrated = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startDate)]))
            Harness.expectEqual(migrated.count, expected.count, "aantal ritten na migratie")
            Harness.expectEqual(migrated.count, 3, "controle: er is echt data gemigreerd, geen lege store")

            for want in expected.sorted(by: { $0.startDate < $1.startDate }) {
                guard let got = migrated.first(where: { $0.id == want.id }) else {
                    Harness.expect(false, "rit \(want.id) is verdwenen bij de migratie")
                    continue
                }
                Harness.expectEqual(got.startDate, want.startDate, "startDate")
                Harness.expectEqual(got.endDate, want.endDate, "endDate")
                Harness.expectEqual(got.startAddress, want.startAddress, "startAddress")
                Harness.expectEqual(got.endAddress, want.endAddress, "endAddress")
                Harness.expectEqual(got.startLatitude, want.startLatitude, "startLatitude")
                Harness.expectEqual(got.startLongitude, want.startLongitude, "startLongitude")
                Harness.expectEqual(got.endLatitude, want.endLatitude, "endLatitude")
                Harness.expectEqual(got.endLongitude, want.endLongitude, "endLongitude")
                Harness.expectEqual(got.distanceKm, want.distanceKm, "distanceKm")
                Harness.expectEqual(got.startOdometer, want.startOdometer, "startOdometer")
                Harness.expectEqual(got.endOdometer, want.endOdometer, "endOdometer")
                Harness.expectEqual(got.categoryRawValue, want.categoryRawValue, "categorie")
                Harness.expectEqual(got.note, want.note, "note")
                Harness.expectEqual(got.clientLabel, want.clientLabel, "clientLabel")
                Harness.expectEqual(got.isAutomaticallyRecorded, want.isAutomaticallyRecorded, "isAutomaticallyRecorded")
                Harness.expectEqual(got.routeData, want.routeData, "routeData")
                Harness.expectEqual(got.vehicle?.name, want.vehicleName, "gekoppeld voertuig")

                // De nieuwe velden staan leeg en niemand is verwijderd.
                Harness.expectEqual(got.destinationPlace, "", "nieuw veld leeg")
                Harness.expectEqual(got.purpose, "", "nieuw veld leeg")
                Harness.expect(!got.isDeleted, "geen enkele rit mag als verwijderd binnenkomen")
            }

            // Voertuig, instellingen en regels overleven het ook.
            let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
            Harness.expectEqual(vehicles.count, 1, "aantal voertuigen")
            Harness.expectEqual(vehicles.first?.licensePlate, "XX-123-Y", "kenteken")
            Harness.expectEqual(vehicles.first?.initialOdometer, 34_180, "beginstand")
            Harness.expectEqual(vehicles.first?.trips.count, 2, "ritten aan het voertuig gekoppeld")

            let settings = try context.fetch(FetchDescriptor<AppSettings>())
            Harness.expectEqual(settings.count, 1, "aantal instellingen")
            Harness.expectEqual(settings.first?.reimbursementRatePerKm, 0.19, "eigen tarief blijft staan")
            Harness.expectEqual(settings.first?.trackingModeRawValue, "hybride", "registratiemodus")
            Harness.expectEqual(settings.first?.workWeekdaysRawValue, "2,3,4", "werkdagen")
            // Bestaande gebruikers komen op Nederland uit, niet op Duitsland.
            Harness.expectEqual(settings.first?.taxRegion, .netherlands, "bestaande installatie blijft Nederlands")

            let rules = try context.fetch(FetchDescriptor<ClassificationRule>())
            Harness.expectEqual(rules.count, 1, "classificatieregels")
            Harness.expectEqual(rules.first?.timesUsed, 4, "leerteller")

            let addresses = try context.fetch(FetchDescriptor<CachedAddress>())
            Harness.expectEqual(addresses.count, 1, "adres-cache")

            // De nieuwe entiteit bestaat en is leeg.
            Harness.expect(try context.fetch(FetchDescriptor<TripRevision>()).isEmpty, "nog geen revisies")
        }

        Harness.suite("Migratie: tweede keer openen blijft werken") {
            // Een al gemigreerde database moet gewoon opnieuw te openen zijn.
            let url = temporaryStoreURL()
            defer { try? FileManager.default.removeItem(at: url) }

            for _ in 0..<2 {
                let configuration = ModelConfiguration(schema: AppSchema.schema, url: url)
                let container = try ModelContainer(
                    for: AppSchema.schema,
                    migrationPlan: AppSchema.migrationPlan,
                    configurations: configuration
                )
                let context = ModelContext(container)
                context.insert(Trip(startDate: .now, distanceKm: 1))
                try context.save()
            }
            let configuration = ModelConfiguration(schema: AppSchema.schema, url: url)
            let container = try ModelContainer(
                for: AppSchema.schema, migrationPlan: AppSchema.migrationPlan, configurations: configuration
            )
            Harness.expectEqual(
                try ModelContext(container).fetch(FetchDescriptor<Trip>()).count, 2,
                "beide ritten blijven bestaan"
            )
        }
    }
}
