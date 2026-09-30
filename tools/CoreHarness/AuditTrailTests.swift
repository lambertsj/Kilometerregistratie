import Foundation
import SwiftData

/// Tests op de audit trail: elke wijziging aan een vastgelegde rit moet een
/// revisie opleveren, revisies mogen nooit verdwijnen, en Nederland mag er
/// niets van merken.
enum AuditTrailTests {
    private static func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSchema.schema, configurations: configuration)
        return ModelContext(container)
    }

    private static func finishedTrip(distanceKm: Double = 30) -> Trip {
        Trip(
            startDate: Fixtures.date(2026, 3, 2, 9, 0),
            endDate: Fixtures.date(2026, 3, 2, 10, 0),
            distanceKm: distanceKm,
            category: .business
        )
    }

    static func run() {
        Harness.suite("Audit: elke wijziging levert een revisie op") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let trip = finishedTrip()
            try writer.create(trip)

            try writer.update(trip) { $0.distanceKm = 42 }

            let revisions = try writer.revisions(for: trip.id)
            Harness.expectEqual(revisions.count, 2, "aanmaken + wijzigen")
            Harness.expectEqual(revisions.first?.changeKind, .created, "eerste revisie is 'aangemaakt'")

            let update = revisions.last
            Harness.expectEqual(update?.changeKind, .updated, "tweede revisie is 'gewijzigd'")
            Harness.expectEqual(update?.field, .distanceKm, "gewijzigd veld")
            Harness.expectEqual(update?.previousValue, "30", "oude waarde")
            Harness.expectEqual(update?.newValue, "42", "nieuwe waarde")
        }

        Harness.suite("Audit: meerdere velden in één wijziging") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let trip = finishedTrip()
            try writer.create(trip)

            try writer.update(trip) { trip in
                trip.category = .personal
                trip.purpose = "Urlaub"
                trip.note = "aangepast"
            }
            let fields = try writer.revisions(for: trip.id)
                .filter { $0.changeKind == .updated }
                .compactMap(\.field)
            Harness.expectEqual(Set(fields), [.category, .purpose, .note], "alle drie de velden vastgelegd")
        }

        Harness.suite("Audit: een wijziging die niets verandert levert niets op") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let trip = finishedTrip()
            try writer.create(trip)
            try writer.update(trip) { $0.distanceKm = 30 }
            Harness.expectEqual(try writer.revisions(for: trip.id).count, 1, "alleen de aanmaakrevisie")
        }

        Harness.suite("Audit: lopende rit levert geen revisiespam op") {
            // Zolang een rit nog loopt (geen eindtijd) schrijft de GPS-opname
            // continu route en afstand weg. Dat is het opbouwen van de
            // registratie, geen wijziging achteraf.
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let trip = Trip(startDate: Fixtures.date(2026, 3, 2, 9, 0), distanceKm: 0)
            try writer.create(trip)

            for km in 1...20 {
                try writer.update(trip) { $0.distanceKm = Double(km) }
            }
            Harness.expectEqual(try writer.revisions(for: trip.id).count, 1, "alleen de aanmaakrevisie")

            // Zodra de rit is afgesloten, telt alles wél weer mee.
            try writer.update(trip) { $0.endDate = Fixtures.date(2026, 3, 2, 10, 0) }
            try writer.update(trip) { $0.distanceKm = 999 }
            Harness.expectEqual(
                try writer.revisions(for: trip.id).filter { $0.field == .distanceKm }.count, 1,
                "wijziging ná afsluiten wordt wél vastgelegd"
            )
        }

        Harness.suite("Audit: zeitnah-venster") {
            let context = try makeContext()
            let tripStart = Fixtures.date(2026, 3, 2, 9, 0)

            // Binnen zeven dagen.
            let early = TripWriteService(
                context: context, ruleSet: GermanyRuleSet(),
                now: { tripStart.addingTimeInterval(3 * 24 * 60 * 60) }
            )
            let tripA = finishedTrip()
            try early.create(tripA)
            try early.update(tripA) { $0.note = "binnen het venster" }
            Harness.expect(
                try early.revisions(for: tripA.id).last?.wasContemporaneous == true,
                "wijziging binnen zeven dagen geldt als tijdig"
            )

            // Erbuiten.
            let late = TripWriteService(
                context: context, ruleSet: GermanyRuleSet(),
                now: { tripStart.addingTimeInterval(30 * 24 * 60 * 60) }
            )
            let tripB = finishedTrip()
            try late.create(tripB)
            try late.update(tripB) { $0.note = "veel later" }
            Harness.expect(
                try late.revisions(for: tripB.id).last?.wasContemporaneous == false,
                "wijziging na dertig dagen geldt niet als tijdig"
            )
            // Maar hij wordt wél gewoon vastgelegd en niet geweigerd.
            Harness.expectEqual(try late.revisions(for: tripB.id).count, 2, "wijziging is vastgelegd, niet geblokkeerd")
        }

        Harness.suite("Audit: verwijderen is een tombstone, geen echte delete") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let trip = finishedTrip()
            try writer.create(trip)
            let id = trip.id

            try writer.delete(trip)

            // De rit bestaat nog in de database …
            let all = try context.fetch(FetchDescriptor<Trip>())
            Harness.expectEqual(all.count, 1, "rit bestaat nog")
            Harness.expect(all.first?.isDeleted == true, "rit is gemarkeerd als verwijderd")

            // … maar komt niet meer terug in lijsten en rapporten.
            let visible = try TripRepository(context: context).trips()
            Harness.expect(visible.isEmpty, "verwijderde rit staat niet meer in de lijst")

            // En de revisies zijn er nog.
            let revisions = try writer.revisions(for: id)
            Harness.expectEqual(revisions.last?.changeKind, .deleted, "verwijdering is vastgelegd")
        }

        Harness.suite("Audit: revisies overleven het verwijderen van de rit") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let trip = finishedTrip()
            try writer.create(trip)
            try writer.update(trip) { $0.note = "gewijzigd" }
            let id = trip.id
            try writer.delete(trip)
            Harness.expectEqual(try writer.revisions(for: id).count, 3, "aanmaken + wijzigen + verwijderen")
        }

        Harness.suite("Audit: Nederland gedraagt zich als voorheen") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: NetherlandsRuleSet())
            let trip = finishedTrip()
            try writer.create(trip)
            try writer.update(trip) { $0.distanceKm = 42 }

            Harness.expect(try writer.revisions(for: trip.id).isEmpty, "NL schrijft geen revisies")

            try writer.delete(trip)
            Harness.expect(
                try context.fetch(FetchDescriptor<Trip>()).isEmpty,
                "NL verwijdert een rit echt, zoals voorheen"
            )
        }

        Harness.suite("Audit: elk veld van Trip zit in de momentopname") {
            // Vangt op dat een nieuw veld op Trip vergeten wordt in de
            // audit trail. Elk veld uit TripAuditField moet een wijziging
            // opleveren die ook echt vastgelegd wordt.
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let vehicle = Vehicle(name: "Testauto")
            context.insert(vehicle)

            let trip = finishedTrip()
            try writer.create(trip)
            try writer.update(trip) { trip in
                trip.startDate = Fixtures.date(2026, 4, 1, 8, 0)
                trip.endDate = Fixtures.date(2026, 4, 1, 9, 0)
                trip.startAddress = "A"
                trip.endAddress = "B"
                trip.distanceKm = 77
                trip.startOdometer = 1000
                trip.endOdometer = 1077
                trip.category = .commute
                trip.note = "n"
                trip.clientLabel = "c"
                trip.vehicle = vehicle
                trip.destinationPlace = "p"
                trip.destinationStreet = "s"
                trip.purpose = "d"
                trip.businessPartner = "r"
                trip.detourNote = "u"
            }
            let changed = Set(try writer.revisions(for: trip.id).compactMap(\.field))
            for field in TripAuditField.allCases {
                Harness.expect(changed.contains(field), "veld \(field.rawValue) wordt niet vastgelegd")
            }
        }

        Harness.suite("Audit: samenvoegen loopt ook via de audit trail") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let earlier = Trip(
                startDate: Fixtures.date(2026, 3, 2, 9, 0),
                endDate: Fixtures.date(2026, 3, 2, 9, 30),
                distanceKm: 10, category: .business
            )
            let later = Trip(
                startDate: Fixtures.date(2026, 3, 2, 9, 40),
                endDate: Fixtures.date(2026, 3, 2, 10, 0),
                distanceKm: 5, category: .business
            )
            try writer.create(earlier)
            try writer.create(later)

            try TripRepository(context: context).merge(later, into: earlier, using: writer)

            Harness.expect(
                try writer.revisions(for: earlier.id).contains { $0.field == .distanceKm },
                "de samengevoegde afstand is vastgelegd"
            )
            Harness.expect(
                try writer.revisions(for: later.id).contains { $0.changeKind == .deleted },
                "de verdwenen rit is als verwijderd vastgelegd"
            )
            Harness.expect(later.isDeleted, "de verdwenen rit is een tombstone")
        }

        Harness.suite("Audit: voertuig met ritten kan niet verwijderd worden") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let vehicle = Vehicle(name: "Firmenwagen")
            context.insert(vehicle)
            let trip = finishedTrip()
            trip.vehicle = vehicle
            try writer.create(trip)

            let repository = VehicleRepository(context: context)
            do {
                try repository.delete(vehicle, ruleSet: GermanyRuleSet())
                Harness.expect(false, "verwijderen had geweigerd moeten worden")
            } catch let error as VehicleRepository.DeletionRefusal {
                Harness.expect(
                    error.errorDescription?.isEmpty == false,
                    "weigering moet een leesbare reden hebben"
                )
            }
            Harness.expectEqual(try context.fetch(FetchDescriptor<Vehicle>()).count, 1, "voertuig bestaat nog")

            // In Nederland mag het wél, net als voorheen.
            try repository.delete(vehicle, ruleSet: NetherlandsRuleSet())
            Harness.expect(try context.fetch(FetchDescriptor<Vehicle>()).isEmpty, "NL verwijdert het voertuig")
        }
    }
}
