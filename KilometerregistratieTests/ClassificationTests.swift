import XCTest
import SwiftData
@testable import Kilometerregistratie

final class ClassificationTests: XCTestCase {
    private let schedule = WorkSchedule(enabled: true, startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [2, 3, 4, 5, 6])

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testWorkScheduleBoundaries() {
        // Woensdag 15 juli 2026.
        XCTAssertTrue(schedule.contains(date(2026, 7, 15, hour: 10)))
        XCTAssertFalse(schedule.contains(date(2026, 7, 15, hour: 20)))
        // Zondag valt buiten de werkdagen.
        XCTAssertFalse(schedule.contains(date(2026, 7, 19, hour: 12)))
    }

    func testSuggestionPriority() {
        let evening = date(2026, 7, 15, hour: 20)
        // Geleerd > kantooruren-regel.
        XCTAssertEqual(TripClassifier.suggestCategory(startDate: evening, learned: .commute, schedule: schedule), .commute)
        // Kantooruren-regel: avond → privé.
        XCTAssertEqual(TripClassifier.suggestCategory(startDate: evening, learned: nil, schedule: schedule), .personal)
        // Binnen werktijd → zakelijk.
        XCTAssertEqual(TripClassifier.suggestCategory(startDate: date(2026, 7, 15, hour: 10), learned: nil, schedule: schedule), .business)
        // Zonder regel altijd zakelijk (snelste declaratie-flow).
        let disabled = WorkSchedule(enabled: false, startMinute: 0, endMinute: 0, weekdays: [])
        XCTAssertEqual(TripClassifier.suggestCategory(startDate: evening, learned: nil, schedule: disabled), .business)
    }

    func testRouteKeyNormalization() {
        XCTAssertEqual(
            TripClassifier.routeKey(startAddress: "  Dorpsstraat 1,  Ons Dorp ", endAddress: "Kantoorlaan 5"),
            "dorpsstraat 1, ons dorp|kantoorlaan 5"
        )
        XCTAssertNil(TripClassifier.routeKey(startAddress: "", endAddress: "Kantoorlaan 5"))
        XCTAssertNil(TripClassifier.routeKey(startAddress: "  ", endAddress: ""))
    }

    func testRuleRepositoryLearnsAndOverwrites() throws {
        let configuration = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try ModelContainer(for: AppSchema.schema, configurations: [configuration]))
        let repository = ClassificationRuleRepository(context: context)
        let key = TripClassifier.routeKey(startAddress: "Thuis 1", endAddress: "Werk 2")!

        XCTAssertNil(repository.learnedCategory(forRouteKey: key))
        try repository.learn(routeKey: key, category: .commute)
        XCTAssertEqual(repository.learnedCategory(forRouteKey: key), .commute)

        try repository.learn(routeKey: key, category: .personal)
        XCTAssertEqual(repository.learnedCategory(forRouteKey: key), .personal)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ClassificationRule>()).count, 1)
    }
}
