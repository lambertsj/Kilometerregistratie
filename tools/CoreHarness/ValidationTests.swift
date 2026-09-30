import Foundation

/// Tests op de controle van een sluitende, volledige registratie.
enum ValidationTests {
    private static let germany: any RegionRuleSet = GermanyRuleSet()
    private static let netherlands: any RegionRuleSet = NetherlandsRuleSet()

    private static let car = UUID()

    /// Een volledig ingevulde Duitse zakelijke rit; losse tests laten er
    /// steeds één ding aan ontbreken.
    private static func completeBusinessTrip(
        id: UUID = UUID(),
        day: Int,
        startOdometer: Double?,
        endOdometer: Double?,
        vehicleID: UUID? = car
    ) -> TripValidationInput {
        TripValidationInput(
            id: id,
            startDate: Fixtures.date(2026, 3, day, 9, 0),
            endDate: Fixtures.date(2026, 3, day, 10, 0),
            startOdometer: startOdometer,
            endOdometer: endOdometer,
            distanceKm: (endOdometer ?? 0) - (startOdometer ?? 0),
            category: .business,
            vehicleID: vehicleID,
            fieldValues: [
                .destinationPlace: "München",
                .destinationStreet: "Leopoldstraße 12",
                .purpose: "Projektbesprechung",
                .businessPartner: "Meier GmbH",
            ]
        )
    }

    static func run() {
        Harness.suite("Validatie: sluitende reeks is in orde") {
            let trips = [
                completeBusinessTrip(day: 2, startOdometer: 48_000, endOdometer: 48_210),
                completeBusinessTrip(day: 3, startOdometer: 48_210, endOdometer: 48_300),
            ]
            let issues = LogValidator.validate(trips: trips, ruleSet: germany)
            Harness.expect(issues.isEmpty, "verwachtte geen meldingen, kreeg \(issues.map(\.kind))")
        }

        Harness.suite("Validatie: gat in de kilometerstanden") {
            // Het voorbeeld uit de opdracht: 48.210 → 48.260 is 50 km die
            // nergens verantwoord is.
            let first = UUID(), second = UUID()
            let trips = [
                completeBusinessTrip(id: first, day: 2, startOdometer: 48_000, endOdometer: 48_210),
                completeBusinessTrip(id: second, day: 3, startOdometer: 48_260, endOdometer: 48_300),
            ]
            let issues = LogValidator.validate(trips: trips, ruleSet: germany)
            let gaps = issues.filter {
                if case .odometerGap = $0.kind { return true } else { return false }
            }
            Harness.expectEqual(gaps.count, 1, "aantal gatmeldingen")
            if case .odometerGap(let km) = gaps.first?.kind {
                Harness.expectClose(km, 50, "grootte van het gat")
            }
            Harness.expectEqual(gaps.first?.severity, .blocking, "een gat is blokkerend")
            Harness.expectEqual(gaps.first?.tripIDs, [first, second], "beide betrokken ritten")
            Harness.expectEqual(gaps.first?.primaryTripID, second, "sprong naar de tweede rit")
        }

        Harness.suite("Validatie: overlappende kilometerstanden") {
            let trips = [
                completeBusinessTrip(day: 2, startOdometer: 48_000, endOdometer: 48_210),
                completeBusinessTrip(day: 3, startOdometer: 48_150, endOdometer: 48_300),
            ]
            let issues = LogValidator.validate(trips: trips, ruleSet: germany)
            let overlaps = issues.compactMap { issue -> Double? in
                if case .odometerOverlap(let km) = issue.kind { return km } else { return nil }
            }
            Harness.expectEqual(overlaps.count, 1, "aantal overlapmeldingen")
            Harness.expectClose(overlaps.first ?? 0, 60, "grootte van de overlap")
        }

        Harness.suite("Validatie: gaten worden niet stilzwijgend gedicht") {
            // De invoer mag niet gewijzigd worden door de validatie; die
            // rapporteert alleen.
            let trips = [
                completeBusinessTrip(day: 2, startOdometer: 48_000, endOdometer: 48_210),
                completeBusinessTrip(day: 3, startOdometer: 48_260, endOdometer: 48_300),
            ]
            let before = trips
            _ = LogValidator.validate(trips: trips, ruleSet: germany)
            Harness.expectEqual(trips, before, "invoer blijft ongewijzigd")
        }

        Harness.suite("Validatie: ontbrekende verplichte velden per categorie") {
            // Zakelijk: alles verplicht.
            let incompleteBusiness = TripValidationInput(
                id: UUID(),
                startDate: Fixtures.date(2026, 3, 2, 9, 0),
                endDate: Fixtures.date(2026, 3, 2, 10, 0),
                startOdometer: 48_000, endOdometer: 48_100,
                distanceKm: 100, category: .business, vehicleID: car,
                fieldValues: [.destinationPlace: "München"]
            )
            let issues = LogValidator.validate(trips: [incompleteBusiness], ruleSet: germany)
            let missing = issues.compactMap { issue -> TripField? in
                if case .missingRequiredField(let field) = issue.kind { return field } else { return nil }
            }
            Harness.expect(missing.contains(.destinationStreet), "straat ontbreekt")
            Harness.expect(missing.contains(.purpose), "reisdoel ontbreekt")
            Harness.expect(missing.contains(.businessPartner), "zakenrelatie ontbreekt")
            Harness.expect(!missing.contains(.destinationPlace), "plaats is wél ingevuld")

            // Privé: alleen kilometers. Dezelfde lege velden mogen hier géén
            // melding opleveren — dat is de wettelijke asymmetrie.
            let personal = TripValidationInput(
                id: UUID(),
                startDate: Fixtures.date(2026, 3, 2, 19, 0),
                endDate: Fixtures.date(2026, 3, 2, 20, 0),
                startOdometer: 48_100, endOdometer: 48_120,
                distanceKm: 20, category: .personal, vehicleID: car
            )
            let personalIssues = LogValidator.validate(trips: [personal], ruleSet: germany)
            Harness.expect(personalIssues.isEmpty, "privérit met alleen kilometers is volledig, kreeg \(personalIssues.map(\.kind))")

            // Woon-werk: korte aantekening volstaat, maar is wél verplicht.
            let commuteWithoutNote = TripValidationInput(
                id: UUID(),
                startDate: Fixtures.date(2026, 3, 3, 8, 0),
                endDate: Fixtures.date(2026, 3, 3, 8, 30),
                startOdometer: 48_120, endOdometer: 48_140,
                distanceKm: 20, category: .commute, vehicleID: car
            )
            let commuteIssues = LogValidator.validate(trips: [commuteWithoutNote], ruleSet: germany)
            Harness.expect(
                commuteIssues.contains { $0.kind == .missingRequiredField(.annotation) },
                "woon-werkrit zonder aantekening moet gemeld worden"
            )

            let commuteWithNote = TripValidationInput(
                id: UUID(),
                startDate: Fixtures.date(2026, 3, 3, 8, 0),
                endDate: Fixtures.date(2026, 3, 3, 8, 30),
                startOdometer: 48_120, endOdometer: 48_140,
                distanceKm: 20, category: .commute, vehicleID: car,
                fieldValues: [.annotation: "Büro"]
            )
            Harness.expect(
                LogValidator.validate(trips: [commuteWithNote], ruleSet: germany).isEmpty,
                "woon-werkrit met aantekening is volledig"
            )
        }

        Harness.suite("Validatie: ontbrekende kilometerstand") {
            let trip = completeBusinessTrip(day: 2, startOdometer: nil, endOdometer: 48_210)
            let issues = LogValidator.validate(trips: [trip], ruleSet: germany)
            Harness.expect(
                issues.contains { $0.kind == .missingOdometer(.startOdometer) },
                "ontbrekende beginstand moet gemeld worden"
            )
        }

        Harness.suite("Validatie: afstand wijkt af van de kilometerstanden") {
            // 100 km volgens de teller, 60 km genoteerd: wijst op een niet
            // vastgelegde omweg. Waarschuwing, geen blokkade.
            var trip = completeBusinessTrip(day: 2, startOdometer: 48_000, endOdometer: 48_100)
            trip.distanceKm = 60
            let issues = LogValidator.validate(trips: [trip], ruleSet: germany)
            let mismatch = issues.first {
                if case .distanceMismatch = $0.kind { return true } else { return false }
            }
            Harness.expect(mismatch != nil, "verschil moet gemeld worden")
            Harness.expectEqual(mismatch?.severity, .warning, "verschil is een waarschuwing")
        }

        Harness.suite("Validatie: Nederland verandert niet") {
            // Dezelfde ritten die in Duitsland een gat en ontbrekende velden
            // opleveren, mogen in Nederland geen enkele melding geven: daar
            // gelden die eisen niet.
            let trips = [
                completeBusinessTrip(day: 2, startOdometer: 48_000, endOdometer: 48_210),
                completeBusinessTrip(day: 3, startOdometer: 48_260, endOdometer: 48_300),
                TripValidationInput(
                    id: UUID(),
                    startDate: Fixtures.date(2026, 3, 4, 9, 0),
                    endDate: Fixtures.date(2026, 3, 4, 10, 0),
                    distanceKm: 12, category: .business, vehicleID: nil
                ),
            ]
            let issues = LogValidator.validate(trips: trips, ruleSet: netherlands)
            Harness.expect(issues.isEmpty, "NL verwacht geen meldingen, kreeg \(issues.map(\.kind))")
        }

        Harness.suite("Validatie: reeksen per voertuig apart") {
            // Twee auto's die elkaar afwisselen mogen geen vals gat opleveren.
            let other = UUID()
            let trips = [
                completeBusinessTrip(day: 2, startOdometer: 48_000, endOdometer: 48_210, vehicleID: car),
                completeBusinessTrip(day: 3, startOdometer: 10_000, endOdometer: 10_050, vehicleID: other),
                completeBusinessTrip(day: 4, startOdometer: 48_210, endOdometer: 48_260, vehicleID: car),
                completeBusinessTrip(day: 5, startOdometer: 10_050, endOdometer: 10_090, vehicleID: other),
            ]
            let issues = LogValidator.validate(trips: trips, ruleSet: germany)
            Harness.expect(issues.isEmpty, "twee sluitende reeksen, kreeg \(issues.map(\.kind))")
        }

        Harness.suite("Validatie: blokkerend staat vóór waarschuwing") {
            var mismatched = completeBusinessTrip(day: 2, startOdometer: 48_000, endOdometer: 48_100)
            mismatched.distanceKm = 60
            let incomplete = TripValidationInput(
                id: UUID(),
                startDate: Fixtures.date(2026, 3, 3, 9, 0),
                endDate: Fixtures.date(2026, 3, 3, 10, 0),
                startOdometer: 48_100, endOdometer: 48_150,
                distanceKm: 50, category: .business, vehicleID: car
            )
            let issues = LogValidator.validate(trips: [mismatched, incomplete], ruleSet: germany)
            Harness.expect(!issues.isEmpty, "verwachtte meldingen")
            Harness.expectEqual(issues.first?.severity, .blocking, "eerste melding is blokkerend")
            Harness.expect(
                issues.map(\.severity) == issues.map(\.severity).sorted(),
                "meldingen staan op ernst gesorteerd"
            )
        }
    }
}
