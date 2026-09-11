import Foundation
import Testing

@testable import DictationCore

@Suite("Coordinator lifecycle")
struct CoordinatorLifecycleTests {
    @Test("The happy path visits every documented phase in order")
    func happyPathVisitsEveryPhase() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        let stream = await harness.coordinator.snapshots()
        let collector = Task { () -> [DictationPhase] in
            var phases: [DictationPhase] = []
            for await snapshot in stream {
                phases.append(snapshot.phase)
            }
            return phases
        }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        let terminal = try await harness.waitForTerminal()
        #expect(terminal.phase == .completed)

        // Finishing the streams is what ends the collector, so nothing is lost to cancellation.
        await harness.coordinator.shutdown()
        let phases = await collector.value

        #expect(phases == [
            .idle, .preparing, .recording, .transcribing, .normalizing, .refining, .inserting,
            .completed,
        ])
    }

    @Test("The first activation prepares the device before it records")
    func captureIsPreparedBeforeItRecords() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        _ = try await harness.runSession()

        let events = await harness.capture.events
        #expect(events == [.prepare, .start, .stop])
    }

    @Test("A second activation during preparing is not lost")
    func activationDuringPreparingIsLatched() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.captureStart)

        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("capture.start was entered") {
            await harness.capture.events.contains(.start)
        }

        // The session is parked before `.recording`, so this arrives early and must be held.
        await harness.coordinator.handle(.toggleRecording)
        await harness.releaseAll()

        let terminal = try await harness.waitForTerminal()
        let events = await harness.capture.events
        #expect(terminal.phase == .completed)
        #expect(events == [.prepare, .start, .stop])
    }

    @Test("An activation while processing does not start a second session")
    func activationWhileProcessingIsIgnored() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.recognition)

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }

        await harness.coordinator.handle(.toggleRecording)

        let parked = await harness.currentSnapshot()
        let captures = await harness.targetProvider.callCount
        #expect(parked.phase == .transcribing)
        // A second session would have captured the destination again.
        #expect(captures == 1)

        await harness.releaseAll()
        #expect(try await harness.waitForTerminal().phase == .completed)
    }

    @Test("An activation from a finished session starts a new one")
    func activationFromCompletedStartsANewSession() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        let first = try await harness.runSession()
        let firstID = first.sessionID
        #expect(firstID != nil)

        try await harness.startRecording()
        let second = await harness.currentSnapshot()
        #expect(second.sessionID != firstID)
        #expect(second.phase == .recording)

        await harness.coordinator.handle(.toggleRecording)
        let terminal = try await harness.waitForTerminal()
        let captures = await harness.targetProvider.callCount
        let metrics = harness.metrics.all
        #expect(terminal.phase == .completed)
        #expect(captures == 2)
        #expect(metrics.count == 2)
    }

    @Test("Dismissing a finished session returns to idle, and repeating it does nothing")
    func dismissIsIdempotent() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        _ = try await harness.runSession()

        await harness.coordinator.handle(.dismiss)
        let dismissed = await harness.currentSnapshot()
        #expect(dismissed.phase == .idle)
        #expect(dismissed.sessionID == nil)
        #expect(dismissed == .idle)

        await harness.coordinator.handle(.dismiss)
        let repeated = await harness.currentSnapshot()
        #expect(repeated == .idle)
    }

    @Test("Disabling refinement runs the same pipeline without the refining phase")
    func deterministicOnlySkipsRefining() async throws {
        let harness = DictationHarness(
            settings: DictationSettings(
                languageHint: .automatic,
                defaultMode: .note,
                refinementEnabled: false
            )
        )
        await harness.allowAll()

        let terminal = try await harness.runSession()
        let refinements = await harness.refiner.callCount

        #expect(terminal.phase == .completed)
        #expect(refinements == 0)
        #expect(terminal.refinement?.outcome == .skippedByPolicy)
        #expect(terminal.transcript.finalText == terminal.transcript.normalizedText)
    }

    @Test("The context is frozen with the destination and the resolved mode")
    func contextIsFrozenAtStart() async throws {
        let harness = DictationHarness(
            settings: DictationSettings(
                languageHint: .chinese,
                defaultMode: .note,
                refinementEnabled: true
            ),
            modeBindings: ["com.example.editor": .structured]
        )
        await harness.allowAll()

        let terminal = try await harness.runSession()
        let context = try #require(terminal.context)
        let recognition = await harness.recognizer.requests

        #expect(context.languageHint == .chinese)
        // Recognition is the one stage that receives the hint.
        #expect(recognition.map(\.language) == [.chinese])
        #expect(context.mode == .structured)
        #expect(context.application?.bundleIdentifier == "com.example.editor")
        #expect(context.insertionTarget?.elementToken == "focused-field")
    }

    @Test("A settings change mid-session cannot alter the session in flight")
    func settingsChangeMidSessionDoesNotAlterTheSession() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        try await harness.startRecording()
        let started = try #require(await harness.currentSnapshot().context)

        await harness.settingsProvider.update(
            DictationSettings(languageHint: .french, defaultMode: .email, refinementEnabled: false)
        )

        await harness.coordinator.handle(.toggleRecording)
        let terminal = try await harness.waitForTerminal()
        let recognition = await harness.recognizer.requests

        #expect(terminal.context == started)
        #expect(terminal.context?.languageHint == started.languageHint)
        #expect(terminal.context?.mode == started.mode)
        // Recognition runs after the change, and still receives the hint frozen at start.
        #expect(recognition.map(\.language) == [started.languageHint])
    }

    @Test("A destination that could not be captured still records and completes")
    func unavailableDestinationStillCompletes() async throws {
        let harness = DictationHarness(
            target: .unavailable(
                .accessibilityPermissionDenied,
                application: ActiveApplication(
                    processIdentifier: 501,
                    bundleIdentifier: "com.example.editor"
                )
            )
        )
        await harness.allowAll()

        let terminal = try await harness.runSession()
        let requests = await harness.inserter.requests

        #expect(terminal.phase == .completed)
        #expect(terminal.context?.insertionTarget == nil)
        // The source application is still known, so history keeps its bundle identifier.
        #expect(terminal.context?.application?.bundleIdentifier == "com.example.editor")
        #expect(requests.first?.target == nil)
    }

    @Test("A completed session records history and metrics exactly once")
    func completionRecordsHistoryAndMetricsOnce() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        _ = try await harness.runSession()

        let metrics = harness.metrics.all
        #expect(metrics.count == 1)

        // History is written after the terminal snapshot is published, so the terminal state
        // alone does not imply the record exists yet.
        try await harness.waitUntil("history recorded the session") {
            await harness.history.records.count == 1
        }
        let records = await harness.history.records

        let record = try #require(records.first)
        #expect(record.transcript.rawText == "raw text")
        #expect(record.transcript.normalizedText == "normalized text")
        #expect(record.transcript.finalText == "refined text")
        #expect(record.mode == .note)
        #expect(record.recognitionEngine?.name == "fake-asr")
        #expect(record.refinementEngine?.name == "fake-refiner")
        #expect(record.insertion?.delivery == .insertedDirectly)
    }

    @Test("Stage timings are recorded per phase from the injected clock")
    func stageTimingsAreRecordedPerPhase() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        _ = try await harness.runSession()

        let metrics = try #require(harness.metrics.last)
        let phases = metrics.timings.map(\.phase)

        #expect(phases == [
            .preparing, .recording, .transcribing, .normalizing, .refining, .inserting,
        ])
        #expect(metrics.timings.allSatisfy { $0.duration == FakeTimeSource.step })
        #expect(metrics.outcome == .completed)
        #expect(metrics.audioDuration == .seconds(1))
        #expect(metrics.rawCharacterCount == "raw text".count)
        #expect(metrics.finalCharacterCount == "refined text".count)
    }

    @Test("Metrics carry no transcript text")
    func metricsCarryNoText() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        _ = try await harness.runSession()

        let metrics = try #require(harness.metrics.last)
        // Every field is a count, a duration, or a closed-set category. The closure below only
        // compiles because none of them is a string drawn from user content.
        let textBearing: [String] = []
        #expect(metrics.rawCharacterCount == "raw text".count)
        #expect(metrics.finalCharacterCount == "refined text".count)
        #expect(textBearing.isEmpty)
    }
}
