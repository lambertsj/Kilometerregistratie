import XCTest
@testable import Kilometerregistratie

@MainActor
final class VirtualClockTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testTimersFireInOrderWhileAdvancing() async {
        let clock = VirtualClock(start: start)
        var fired: [String] = []
        _ = clock.every(30) { fired.append("a@\(Int(clock.now.timeIntervalSince(self.start)))") }
        _ = clock.every(45) { fired.append("b@\(Int(clock.now.timeIntervalSince(self.start)))") }

        await clock.advance(to: start.addingTimeInterval(100))

        XCTAssertEqual(fired, ["a@30", "b@45", "a@60", "a@90", "b@90"])
        XCTAssertEqual(clock.now, start.addingTimeInterval(100))
    }

    func testDisabledTimersDoNotFireAndFireOnceOnResume() async {
        let clock = VirtualClock(start: start)
        var count = 0
        _ = clock.every(30) { count += 1 }

        clock.timersEnabled = false
        await clock.advance(to: start.addingTimeInterval(600))
        XCTAssertEqual(count, 0, "opgeschorte app voert geen timers uit (A3)")

        await clock.resumeTimers()
        XCTAssertEqual(count, 1, "na hervatten vuurt een verlopen timer één keer")
    }

    func testCancelledTimerStopsFiring() async {
        let clock = VirtualClock(start: start)
        var count = 0
        let handle = clock.every(30) { count += 1 }
        await clock.advance(to: start.addingTimeInterval(30))
        handle.cancel()
        await clock.advance(to: start.addingTimeInterval(300))
        XCTAssertEqual(count, 1)
    }
}
