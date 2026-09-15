import DictationCore
import Foundation
import Testing

@testable import DictationDemo

/// A real coordinator over the demo adapters, paced by a manual clock.
struct DemoDriver {
    let clock = ManualClock()
    let scenarios: DemoScenarioSelector
    let coordinator: DictationCoordinator

    init(_ scenario: DemoScenario = .success, settings: DictationSettings = .standard) {
        scenarios = DemoScenarioSelector(scenario)
        coordinator = DictationCoordinator(
            dependencies: DemoDependencies.make(
                scenarios: scenarios,
                clock: clock,
                settings: settings
            )
        )
    }

    struct TimedOut: Error, CustomStringConvertible {
        let condition: String
        var description: String { "Timed out waiting until \(condition)" }
    }

    /// Advances the clock in small steps until `condition` holds.
    @discardableResult
    func advance(
        until condition: String,
        attempts: Int = 5_000,
        _ holds: (SessionSnapshot) -> Bool
    ) async throws -> SessionSnapshot {
        for _ in 0..<attempts {
            let snapshot = await coordinator.currentSnapshot()
            if holds(snapshot) { return snapshot }
            clock.advance(by: .milliseconds(50))
            for _ in 0..<4 { await Task.yield() }
        }
        throw TimedOut(condition: condition)
    }

    @discardableResult
    func advance(to phase: DictationPhase) async throws -> SessionSnapshot {
        try await advance(until: "the session reached \(phase)") { $0.phase == phase }
    }

    func startRecording() async throws {
        await coordinator.handle(.toggleRecording)
        try await advance(to: .recording)
        // Let the recording run for a while, so the clip has a length.
        clock.advance(by: .seconds(2))
    }

    /// Press, record, press, and wait for the session to end.
    func runSession() async throws -> SessionSnapshot {
        try await startRecording()
        await coordinator.handle(.toggleRecording)
        return try await advance(until: "the session ended") { $0.phase.isTerminal }
    }
}

@Suite("Demo scenarios")
struct DemoScenarioTests {
    @Test("Success inserts the refined text directly")
    func success() async throws {
        let driver = DemoDriver(.success)
        let terminal = try await driver.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.failure == nil)
        #expect(terminal.fallbacks.isEmpty)
        #expect(terminal.refinement?.outcome == .refined(DemoText.refinementEngine))
        #expect(terminal.transcript.finalText == DemoText.refined)
        #expect(terminal.insertion == InsertionOutcome(delivery: .insertedDirectly, verification: .confirmed))
        #expect(terminal.audio?.origin == .testFixture)
        #expect((terminal.audio?.duration ?? .zero) > .zero)
        await driver.coordinator.shutdown()
    }

    @Test("Refinement fallback keeps the deterministic text")
    func refinementFallback() async throws {
        let driver = DemoDriver(.refinementFallback)
        let terminal = try await driver.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.fallbacks == [.refinementTimedOut])
        #expect(terminal.refinement?.outcome == .unavailable(.refinementTimedOut))
        #expect(terminal.transcript.finalText == DemoText.normalized)
        #expect(terminal.insertion?.delivery == .insertedDirectly)
        await driver.coordinator.shutdown()
    }

    @Test("Copied-only delivery completes with the text left on the clipboard")
    func copiedOnly() async throws {
        let driver = DemoDriver(.copiedOnly)
        let terminal = try await driver.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.insertion == .copiedOnly(.targetUnavailable))
        #expect(terminal.transcript.finalText == DemoText.refined)
        await driver.coordinator.shutdown()
    }

    @Test("Recognition failure fails the session at transcription")
    func recognitionFailure() async throws {
        let driver = DemoDriver(.recognitionFailure)
        let terminal = try await driver.runSession()

        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.stage == .transcribing)
        #expect(terminal.failure?.category == .runtimeFailure)
        #expect(terminal.failure?.recoverability == .recoverable)
        #expect(terminal.transcript == .empty)
        await driver.coordinator.shutdown()
    }

    @Test("No speech fails the session before recognition")
    func noSpeech() async throws {
        let driver = DemoDriver(.noSpeech)
        let terminal = try await driver.runSession()

        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.stage == .transcribing)
        #expect(terminal.failure?.category == .noSpeechDetected)
        #expect(terminal.transcript == .empty)
        await driver.coordinator.shutdown()
    }

    @Test("Every scenario reaches a terminal phase", arguments: DemoScenario.allCases)
    func everyScenarioTerminates(_ scenario: DemoScenario) async throws {
        let driver = DemoDriver(scenario)
        let terminal = try await driver.runSession()
        #expect(terminal.phase.isTerminal)
        await driver.coordinator.shutdown()
    }

    @Test("A deterministic-only session never reaches the scripted refiner")
    func deterministicOnly() async throws {
        let driver = DemoDriver(
            .refinementFallback,
            settings: DictationSettings(
                languageHint: .automatic,
                defaultMode: .note,
                refinementEnabled: false
            )
        )
        let terminal = try await driver.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.refinement?.outcome == .skippedByPolicy)
        #expect(terminal.fallbacks.isEmpty)
        await driver.coordinator.shutdown()
    }

    // MARK: - Selection changes

    @Test("Changing the scenario while recording affects only the next session")
    func changeWhileRecording() async throws {
        let driver = DemoDriver(.success)

        try await driver.startRecording()
        driver.scenarios.selection = .recognitionFailure
        await driver.coordinator.handle(.toggleRecording)
        let first = try await driver.advance(until: "the first session ended") {
            $0.phase.isTerminal
        }
        #expect(first.phase == .completed)

        let second = try await driver.runSession()
        #expect(second.phase == .failed)
        #expect(second.failure?.category == .runtimeFailure)
        await driver.coordinator.shutdown()
    }

    @Test("Changing the scenario while processing does not alter the session in flight")
    func changeWhileProcessing() async throws {
        let driver = DemoDriver(.success)

        try await driver.startRecording()
        await driver.coordinator.handle(.toggleRecording)
        try await driver.advance(to: .refining)
        driver.scenarios.selection = .copiedOnly
        let first = try await driver.advance(until: "the first session ended") {
            $0.phase.isTerminal
        }
        #expect(first.insertion?.delivery == .insertedDirectly)

        let second = try await driver.runSession()
        #expect(second.insertion?.delivery == .copiedOnly)
        await driver.coordinator.shutdown()
    }

    @Test("A session's scenario is fixed at its first lookup")
    func selectorFixesFirstLookup() {
        let selector = DemoScenarioSelector(.success)
        let id = SessionID()

        #expect(selector.scenario(for: id, recorded: .noSpeech) == .noSpeech)
        selector.selection = .copiedOnly
        #expect(selector.scenario(for: id) == .noSpeech)
        #expect(selector.scenario(for: id, recorded: .success) == .noSpeech)
        #expect(selector.scenario(for: SessionID()) == .copiedOnly)
    }

    @Test("The selector forgets only the oldest sessions")
    func selectorIsBounded() {
        let selector = DemoScenarioSelector(.success)
        let first = SessionID()
        _ = selector.scenario(for: first)
        for _ in 0..<DemoScenarioSelector.retainedSessions - 1 {
            _ = selector.scenario(for: SessionID())
        }
        selector.selection = .noSpeech
        // Still retained: exactly at the bound.
        #expect(selector.scenario(for: first) == .success)

        _ = selector.scenario(for: SessionID())
        // Evicted by the session that went over the bound.
        #expect(selector.scenario(for: first) == .noSpeech)
    }
}

@Suite("Manual clock")
struct ManualClockTests {
    @Test("A sleeper wakes only once the clock reaches its deadline")
    func sleeperWakesAtDeadline() async throws {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        try await waitUntil { clock.sleeperCount == 1 }

        clock.advance(by: .milliseconds(999))
        #expect(clock.sleeperCount == 1)

        clock.advance(by: .milliseconds(1))
        try await sleeper.value
        #expect(clock.sleeperCount == 0)
        #expect(clock.now.offset == .seconds(1))
    }

    @Test("A cancelled sleeper throws without the clock moving")
    func cancelledSleeperThrows() async throws {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(1)) }
        try await waitUntil { clock.sleeperCount == 1 }

        sleeper.cancel()
        await #expect(throws: CancellationError.self) { try await sleeper.value }
        #expect(clock.sleeperCount == 0)
    }

    @Test("A deadline already passed returns at once")
    func pastDeadlineReturns() async throws {
        let clock = ManualClock()
        clock.advance(by: .seconds(5))
        try await clock.sleep(until: ManualClock.Instant(offset: .seconds(1)))
        #expect(clock.sleeperCount == 0)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("condition never held")
    }
}
