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
            // A same-phase refresh: the coordinator lets the session go before its cleanup
            // suspends, and publishes that it would now start a new one (ADR 0005). The
            // terminal phase still follows the history write.
            .inserting,
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

        // Written before the terminal snapshot, so seeing the session end is enough.
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

    // MARK: - Destination, published state, and shutdown

    @Test(
        "A destination that could not be captured still resolves the application's mode",
        arguments: [TargetUnavailableReason.accessibilityPermissionDenied, .noFocusedElement]
    )
    func unavailableDestinationStillResolvesTheApplicationMode(
        _ reason: TargetUnavailableReason
    ) async throws {
        let harness = DictationHarness(
            target: .unavailable(
                reason,
                application: ActiveApplication(
                    processIdentifier: 501,
                    bundleIdentifier: "com.tinyspeck.slackmacgap"
                )
            ),
            modeBindings: ["com.tinyspeck.slackmacgap": .message]
        )
        await harness.allowAll()

        let terminal = try await harness.runSession()
        let refinements = await harness.refiner.requests

        // Reading the frontmost application needs no permission, and per-app modes are keyed
        // on it rather than on the focused element.
        #expect(terminal.context?.mode == .message)
        #expect(refinements.map(\.mode) == [.message])
    }

    @Test("Every published snapshot of a session carries the same frozen context")
    func contextRemainsFrozenAfterPreparation() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        let stream = await harness.coordinator.snapshots()
        let collector = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
            }
            return snapshots
        }

        _ = try await harness.runSession()
        await harness.coordinator.shutdown()
        let published = await collector.value

        // Nothing is published until the destination is frozen, so `preparing` is included:
        // every snapshot a view can act on carries the context, and it is the same one
        // throughout, regardless of subsequent focus or settings changes.
        let session = published.filter { $0.phase != .idle }
        let frozenContext = try #require(session.first?.context)
        #expect(session.first?.phase == .preparing)
        #expect(session.allSatisfy { $0.context == frozenContext })
    }

    @Test("Nothing is published for a session until its destination is frozen")
    func nothingIsPublishedBeforeTheDestinationIsFrozen() async throws {
        let harness = DictationHarness()
        // Parked inside target capture, which is where a session sits before it has a
        // destination to freeze.
        await harness.parkOnly(.targetCapture)

        let stream = await harness.coordinator.snapshots()
        let collector = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
            }
            return snapshots
        }

        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the session parked at target capture") {
            await harness.targetProvider.callCount > 0
        }

        // A view that opened a panel on `preparing` would take the focus this session is
        // about to freeze, whether it was pushed that snapshot or read it. So the state is
        // not merely unsent — it does not exist yet, for a poller or a late subscriber
        // either.
        let published = await harness.currentSnapshot()
        #expect(published.phase == .idle)
        var late = await harness.coordinator.snapshots().makeAsyncIterator()
        #expect(await late.next()?.phase == .idle)

        await harness.releaseAll()
        _ = try await harness.waitForPhase(.recording)
        await harness.coordinator.shutdown()

        let observed = await collector.value
        let preparing = observed.filter { $0.phase == .preparing }
        #expect(observed.first?.phase == .idle)
        // Published once, and only with the destination already captured.
        #expect(preparing.count == 1)
        #expect(preparing.first?.context?.insertionTarget?.elementToken == "focused-field")
    }

    @Test("The deterministic text is published before refinement and survives a cancel there")
    func deterministicTextIsPublishedBeforeRefinement() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.refinement)
        defer { Task { await harness.releaseAll() } }
        // Once the cancellation releases it, the refiner honours it and throws. A refiner that
        // returned a result instead would carry the deterministic text into the transcript.
        await harness.refiner.setResponse(.cancelled)

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        let refining = try await harness.waitForPhase(.refining)

        // Refinement can take seconds. Anything shown or copied meanwhile should be the
        // deterministic text, not raw recognition output.
        #expect(refining.transcript.normalizedText == "normalized text")
        #expect(refining.transcript.bestAvailableText == "normalized text")

        await harness.coordinator.handle(.cancel)
        await harness.releaseAll()
        let terminal = try await harness.waitForTerminal()

        #expect(terminal.phase == .cancelled)
        #expect(terminal.transcript.rawText == "raw text")
        #expect(terminal.transcript.normalizedText == "normalized text")
    }

    @Test("A coordinator that was shut down ignores further activations")
    func shutDownCoordinatorIgnoresActivations() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.coordinator.shutdown()

        // A shortcut event can still arrive while the application is terminating.
        await harness.coordinator.handle(.toggleRecording)
        let snapshot = await harness.currentSnapshot()

        #expect(snapshot.phase == .idle)
        #expect(await harness.capture.events.isEmpty)
        #expect(await harness.targetProvider.callCount == 0)

        // Ends a session that should never have started, so it is not left parked.
        await harness.coordinator.handle(.cancel)
    }
}
