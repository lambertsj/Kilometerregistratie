import XCTest
@testable import Kilometerregistratie

final class TripMergeTests: XCTestCase {
    private func date(_ minutesFromEpoch: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(minutesFromEpoch * 60))
    }

    func testMergeCombinesDistanceAndKeepsEarlierStart() {
        let earlier = TripMerge.Input(
            startDate: date(0), endDate: date(10),
            startAddress: "Thuis", endAddress: "Station",
            distanceKm: 5, note: "Naar station"
        )
        let later = TripMerge.Input(
            startDate: date(15), endDate: date(40),
            startAddress: "Station", endAddress: "Kantoor",
            distanceKm: 20, note: "Naar kantoor"
        )
        let merged = TripMerge.merge(earlier: earlier, later: later)

        XCTAssertEqual(merged.startDate, date(0))
        XCTAssertEqual(merged.endDate, date(40))
        XCTAssertEqual(merged.startAddress, "Thuis")
        XCTAssertEqual(merged.endAddress, "Kantoor")
        XCTAssertEqual(merged.distanceKm, 25)
        XCTAssertEqual(merged.note, "Naar station / Naar kantoor")
    }

    func testMergeFallsBackToEarlierEndAddressWhenLaterIsEmpty() {
        let earlier = TripMerge.Input(
            startDate: date(0), endDate: date(10),
            startAddress: "Thuis", endAddress: "Station",
            distanceKm: 5, note: ""
        )
        let later = TripMerge.Input(
            startDate: date(15), endDate: nil,
            startAddress: "", endAddress: "",
            distanceKm: 20, note: ""
        )
        let merged = TripMerge.merge(earlier: earlier, later: later)

        XCTAssertEqual(merged.endAddress, "Station")
        XCTAssertEqual(merged.endDate, date(10))
        XCTAssertEqual(merged.note, "")
    }

    func testMergeDoesNotDuplicateIdenticalNotes() {
        let earlier = TripMerge.Input(
            startDate: date(0), endDate: date(10),
            startAddress: "A", endAddress: "B", distanceKm: 1, note: "Klantbezoek"
        )
        let later = TripMerge.Input(
            startDate: date(15), endDate: date(20),
            startAddress: "B", endAddress: "C", distanceKm: 1, note: "Klantbezoek"
        )
        XCTAssertEqual(TripMerge.merge(earlier: earlier, later: later).note, "Klantbezoek")
    }
}
