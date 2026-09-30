import Foundation

/// Minimale test-runner voor de losse swiftc-harness. Bewust zonder XCTest
/// zodat `Core/` op de Mac getest kan worden zonder simulator (zie CLAUDE.md).
enum Harness {
    private(set) static var failures: [String] = []
    private(set) static var checks = 0
    private static var currentSuite = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        do {
            try body()
        } catch {
            fail("wierp onverwacht: \(error)")
        }
    }

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        checks += 1
        if !condition { fail(message()) }
    }

    static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        checks += 1
        if actual != expected {
            fail("\(label): kreeg \(actual), verwachtte \(expected)")
        }
    }

    static func expectClose(_ actual: Double, _ expected: Double, _ label: String, accuracy: Double = 0.0001) {
        checks += 1
        if abs(actual - expected) > accuracy {
            fail("\(label): kreeg \(actual), verwachtte \(expected)")
        }
    }

    /// Vergelijkt tekst met een golden file en print bij verschil de eerste
    /// afwijkende regel, zodat een onbedoelde wijziging direct leesbaar is.
    static func expectMatchesGolden(_ actual: String, golden name: String) {
        checks += 1
        guard let expected = try? String(contentsOfFile: goldenPath(name), encoding: .utf8) else {
            if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
                try? actual.write(toFile: goldenPath(name), atomically: true, encoding: .utf8)
                print("  + golden \(name) aangemaakt")
            } else {
                fail("golden \(name) ontbreekt — schrijf hem met UPDATE_GOLDENS=1")
            }
            return
        }
        guard actual != expected else { return }

        if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
            try? actual.write(toFile: goldenPath(name), atomically: true, encoding: .utf8)
            print("  ↻ golden \(name) bijgewerkt")
            return
        }

        let actualLines = actual.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        let expectedLines = expected.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        var detail = "golden \(name) wijkt af"
        for index in 0..<max(actualLines.count, expectedLines.count) {
            let lhs = index < actualLines.count ? actualLines[index] : "<einde>"
            let rhs = index < expectedLines.count ? expectedLines[index] : "<einde>"
            if lhs != rhs {
                detail += "\n      regel \(index + 1) nu:      \(lhs)\n      regel \(index + 1) golden:  \(rhs)"
                break
            }
        }
        fail(detail)
    }

    static func expectMatchesGolden(_ actual: Data, golden name: String) {
        checks += 1
        guard let expected = FileManager.default.contents(atPath: goldenPath(name)) else {
            if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
                try? actual.write(to: URL(fileURLWithPath: goldenPath(name)))
                print("  + golden \(name) aangemaakt")
            } else {
                fail("golden \(name) ontbreekt — schrijf hem met UPDATE_GOLDENS=1")
            }
            return
        }
        guard actual != expected else { return }

        if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
            try? actual.write(to: URL(fileURLWithPath: goldenPath(name)))
            print("  ↻ golden \(name) bijgewerkt")
            return
        }

        let firstDifference = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        fail(
            "golden \(name) wijkt af: \(actual.count) bytes nu, \(expected.count) bytes golden"
                + (firstDifference.map { ", eerste verschil op byte \($0)" } ?? "")
        )
    }

    private static func fail(_ message: String) {
        failures.append("[\(currentSuite)] \(message)")
        print("  ✗ \(currentSuite): \(message)")
    }

    static func goldenPath(_ name: String) -> String {
        let root = ProcessInfo.processInfo.environment["GOLDEN_DIR"] ?? "tools/goldens"
        return "\(root)/\(name)"
    }

    static func report() -> Int32 {
        print("")
        if failures.isEmpty {
            print("✓ \(checks) checks geslaagd")
            return 0
        }
        print("✗ \(failures.count) van \(checks) checks gefaald:")
        for failure in failures { print("   – \(failure)") }
        return 1
    }
}
