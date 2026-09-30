import Foundation
import SwiftData

/// Tests op de headline-toestand en op `LogValidationRepository`: dat de
/// jaargrens correct wordt afgehandeld (een gat op 31-12/1-1 wordt precies
/// één keer getoond, in het jaar van de tweede rit) en dat Nederland niets
/// van deze controle merkt.
enum LogValidationRepositoryTests {
    private static func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSchema.schema, configurations: configuration)
        return ModelContext(container)
    }

    static func run() {
        Harness.suite("Headline: telt af naar ok/waarschuwingen/blokkerend") {
            Harness.expectEqual(LogHeadlineState(issues: []), .ok, "geen issues")

            let warning = LogIssue(severity: .warning, kind: .unfinishedTrip, tripIDs: [UUID()])
            Harness.expectEqual(LogHeadlineState(issues: [warning]), .warnings(count: 1), "alleen waarschuwingen")

            let blocking = LogIssue(severity: .blocking, kind: .missingVehicle, tripIDs: [UUID()])
            Harness.expectEqual(
                LogHeadlineState(issues: [warning, blocking]), .blocking(count: 1, warningCount: 1),
                "blokkerend wint van waarschuwing, telt beide"
            )
        }

        Harness.suite("Validatierepository: gat op de jaargrens telt in het juiste jaar") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let vehicle = Vehicle(name: "Firmenwagen")
            context.insert(vehicle)

            // Laatste rit van 2025 en eerste van 2026, met een gat ertussen.
            let lastOf2025 = Trip(
                startDate: Fixtures.date(2025, 12, 30, 9, 0), endDate: Fixtures.date(2025, 12, 30, 10, 0),
                distanceKm: 100, startOdometer: 40_000, endOdometer: 40_100,
                category: .business, vehicle: vehicle
            )
            let firstOf2026 = Trip(
                startDate: Fixtures.date(2026, 1, 3, 9, 0), endDate: Fixtures.date(2026, 1, 3, 10, 0),
                distanceKm: 50, startOdometer: 40_150, endOdometer: 40_200,
                category: .business, vehicle: vehicle
            )
            try writer.create(lastOf2025)
            try writer.create(firstOf2026)

            let repository = LogValidationRepository(context: context)
            let issues2025 = try repository.issues(forTaxYear: 2025, ruleSet: GermanyRuleSet())
            let issues2026 = try repository.issues(forTaxYear: 2026, ruleSet: GermanyRuleSet())

            Harness.expect(
                !issues2025.contains { if case .odometerGap = $0.kind { return true }; return false },
                "het gat hoort niet bij 2025: de tweede rit ligt in 2026"
            )
            Harness.expect(
                issues2026.contains { if case .odometerGap = $0.kind { return true }; return false },
                "het gat moet zichtbaar zijn in 2026"
            )
        }

        Harness.suite("Validatierepository: velden buiten het jaar tellen niet mee") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            // Onvolledige rit uit een ander jaar.
            let old = Trip(
                startDate: Fixtures.date(2024, 6, 1, 9, 0), endDate: Fixtures.date(2024, 6, 1, 10, 0),
                distanceKm: 10, category: .business
            )
            try writer.create(old)

            let issues2026 = try LogValidationRepository(context: context)
                .issues(forTaxYear: 2026, ruleSet: GermanyRuleSet())
            Harness.expect(issues2026.isEmpty, "een rit uit 2024 hoort niet in de controle van 2026")

            let issues2024 = try LogValidationRepository(context: context)
                .issues(forTaxYear: 2024, ruleSet: GermanyRuleSet())
            Harness.expect(!issues2024.isEmpty, "de onvolledige rit moet in 2024 wél gemeld worden")
        }

        Harness.suite("Validatierepository: verwijderde ritten tellen niet mee") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: GermanyRuleSet())
            let trip = Trip(
                startDate: Fixtures.date(2026, 3, 2, 9, 0),
                category: .business
            )
            try writer.create(trip)
            try writer.delete(trip)

            let issues = try LogValidationRepository(context: context)
                .issues(forTaxYear: 2026, ruleSet: GermanyRuleSet())
            Harness.expect(issues.isEmpty, "een tombstone hoort niet meer mee te tellen")
        }

        Harness.suite("Validatierepository: Nederland levert geen continuïteitsissues") {
            let context = try makeContext()
            let writer = TripWriteService(context: context, ruleSet: NetherlandsRuleSet())
            try writer.create(Trip(
                startDate: Fixtures.date(2026, 3, 2, 9, 0), endDate: Fixtures.date(2026, 3, 2, 10, 0),
                distanceKm: 30, category: .business
            ))
            try writer.create(Trip(
                startDate: Fixtures.date(2026, 3, 3, 9, 0), endDate: Fixtures.date(2026, 3, 3, 10, 0),
                distanceKm: 999, category: .business
            ))
            let issues = try LogValidationRepository(context: context)
                .issues(forTaxYear: 2026, ruleSet: NetherlandsRuleSet())
            Harness.expect(issues.isEmpty, "NL heeft geen kilometerstand-eisen, dus geen meldingen")
        }
    }
}
