import XCTest
@testable import Kilometerregistratie

/// Deterministische pseudo-random generator, zodat een seed altijd dezelfde
/// reeks stappen oplevert.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class ScenarioFuzzTests: XCTestCase {
    private enum Step: CaseIterable {
        case drive, stand, tunnel, gap, background, suspend, resume, kill, relaunch, revoke, start, stop
    }

    /// Speelt een willekeurige reeks stappen af en controleert de invarianten.
    /// Geeft de afgespeelde stappen terug, voor in de foutmelding.
    @discardableResult
    private func runScenario(seed: UInt64, file: StaticString = #filePath, line: UInt = #line) async throws -> [String] {
        var rng = SeededGenerator(seed: seed)
        var log: [String] = []
        let mode: ScenarioMode = [.manual, .hybrid, .automatic].randomElement(using: &rng)!
        var ios = IOSParameters()
        ios.autoPauseAfter = Double(Int.random(in: 300...1200, using: &rng))   // A2: 5 tot 20 minuten
        ios.wakesWhenUpdatesResume = Bool.random(using: &rng)                  // A4 in beide richtingen
        ios.timersResumeBeforeFirstSample = Bool.random(using: &rng)           // A11 in beide richtingen
        ios.revokingPermissionTerminatesApp = Bool.random(using: &rng)        // A9 in beide richtingen
        ios.batchSize = Int.random(in: 1...4, using: &rng)                     // A12
        let stopAfter = Int.random(in: 1...6, using: &rng)
        log.append("mode=\(mode) stopNa=\(stopAfter)min pauze=\(Int(ios.autoPauseAfter))s wekt=\(ios.wakesWhenUpdatesResume) timersEerst=\(ios.timersResumeBeforeFirstSample) intrekkenBeëindigt=\(ios.revokingPermissionTerminatesApp) batch=\(ios.batchSize)")
        let s = try ScenarioRunner(mode: mode, stopAfterMinutes: stopAfter, ios: ios)

        for _ in 0..<Int.random(in: 4...14, using: &rng) {
            let step = Step.allCases.randomElement(using: &rng)!
            switch step {
            case .drive:
                let meters = Double(Int.random(in: 500...15_000, using: &rng))
                let known = Int.random(in: 0...4, using: &rng) != 0
                log.append("rij \(Int(meters)) m bekendeSnelheid=\(known)")
                await s.drive(meters: meters, speedKnown: known)
            case .stand:
                let seconds = Double(Int.random(in: 30...2400, using: &rng))
                log.append("sta \(Int(seconds)) s")
                await s.stand(for: seconds)
            case .tunnel:
                let meters = Double(Int.random(in: 200...5_000, using: &rng))
                let seconds = Double(Int.random(in: 20...900, using: &rng))
                log.append("sprong \(Int(meters)) m over \(Int(seconds)) s")
                await s.jump(meters: meters, over: seconds)
            case .gap:
                let seconds = Double(Int.random(in: 60...1800, using: &rng))
                log.append("wacht \(Int(seconds)) s")
                await s.wait(for: seconds)
            case .background: log.append("naar achtergrond"); s.appToBackground()
            case .suspend: log.append("opschorten"); s.appSuspend()
            case .resume: log.append("hervatten"); await s.appResume()
            case .kill: log.append("kill"); s.appKill()
            case .relaunch: log.append("heropenen"); await s.appRelaunch()
            case .revoke: log.append("toestemming intrekken"); await s.revokePermission()
            case .start: log.append("START"); try? await s.userTapsStart()
            case .stop: log.append("STOP"); try? await s.userTapsStop()
            }
            try s.assertInvariants(file: file, line: line)
        }

        // Afronden: app draait, tijd verstrijkt, de gebruiker sluit een handmatige rit af.
        log.append("afronden")
        if s.ios.appState == .terminated { await s.appRelaunch() }
        await s.appResume()
        await s.stand(for: 30 * 60)
        // Eerst controleren: een automatische rit moet zichzelf hebben afgesloten,
        // zonder dat de gebruiker op STOP hoeft te tikken.
        s.assertNoOpenAutomaticTrip(file: file, line: line)
        try? await s.userTapsStop()
        try s.assertInvariants(file: file, line: line)
        return log
    }

    /// Aantal seeds; te overschrijven met de omgevingsvariabele FUZZ_SEEDS.
    private var seedCount: UInt64 {
        UInt64(ProcessInfo.processInfo.environment["FUZZ_SEEDS"] ?? "") ?? 100
    }

    /// Stopt bij de eerste mislukte seed en meldt die samen met de stappen.
    func testRandomScenarios() async throws {
        for seed in 1...seedCount {
            let before = testRun?.totalFailureCount ?? 0
            var log: [String] = []
            do {
                log = try await runScenario(seed: seed)
            } catch {
                XCTFail("seed \(seed): \(error)")
            }
            if (testRun?.totalFailureCount ?? 0) > before {
                XCTFail("EERSTE MISLUKTE SEED: \(seed). Stappen: \(log.joined(separator: " | "))")
                return
            }
        }
    }

    // Mislukte seeds komen hier als vaste regressietest, bv.:
    // func testSeed17() async throws { try await runScenario(seed: 17) }

    /// Seed 10: een sample van vlak vóór de STOP-tik komt pas daarna binnen (batch)
    /// en startte een automatische rit die overlapte met de handmatige rit.
    func testSeed10() async throws { try await runScenario(seed: 10) }

    /// Seed 39: een automatische rit met één enkel sample, gekild zonder toestemming,
    /// werd op duur nul afgesloten in plaats van weggegooid.
    func testSeed39() async throws { try await runScenario(seed: 39) }

    /// Seed 508: toestemming ingetrokken na een hervatting; de rit eindigde op het
    /// moment van intrekken in plaats van op het laatste teken van leven.
    func testSeed508() async throws { try await runScenario(seed: 508) }
}
