import Testing

@testable import DictationCore

@Suite("Coordinator cancellation")
struct CoordinatorCancellationTests {
    @Test(
        "Cancelling while parked at an await boundary ends the session",
        arguments: DictationHarness.Boundary.allCases
    )
    func cancelAtEachBoundary(_ boundary: DictationHarness.Boundary) async throws {
        let harness = DictationHarness()
        await harness.parkOnly(boundary)
        // A failed expectation must not leave the driver parked forever.
        defer { Task { await harness.releaseAll() } }

        // Pressing twice is safe at every boundary: the second activation is latched and
        // consumed when the driver reaches its stop wait.
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the session parked at \(boundary.rawValue)") {
            await harness.hasArrived(at: boundary)
        }

        await harness.coordinator.handle(.cancel)
        await harness.releaseAll()
        let terminal = try await harness.waitForTerminal()
        // `.cancelled` is published as soon as the user asks for it, so the run behind it is
        // still unwinding out of the adapter that was parked.
        try await harness.waitForCleanup()

        let events = await harness.capture.events
        let discards = await harness.clip.discardCount
        let metrics = harness.metrics.all

        #expect(terminal.phase == .cancelled)
        #expect(metrics.count == 1)
        #expect(metrics.last?.outcome == .cancelled)

        if boundary == .insertion {
            // Cancellation during delivery must not erase the finished text. Whether an
            // interrupted delivery belongs in history is a separate persistence policy.
            #expect(terminal.transcript.bestAvailableText == "refined text")
        } else {
            #expect(await harness.history.records.isEmpty)
        }

        if boundary.isAfterCaptureStop {
            // Capture already stopped, so the device is not released again.
            #expect(events.count(where: { $0 == .cancel }) == 0)
            #expect(discards == 1)
        } else {
            // Recording never produced a clip, so the device must be released.
            #expect(events.count(where: { $0 == .cancel }) == 1)
            #expect(events.count(where: { $0 == .stop }) == 0)
            #expect(discards == 0)
        }

        if boundary.isBeforeCaptureStart {
            // Cancelled before the device was asked to start, so it must never start. A
            // microphone that turns on after the user cancelled is a privacy failure.
            #expect(!events.contains(.start), "capture events were \(events)")
        }
    }

    @Test("Cancelling before recording starts never stops capture")
    func cancelDuringPreparingNeverStopsCapture() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.captureStart)

        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("capture.start was entered") {
            await harness.capture.events.contains(.start)
        }

        await harness.coordinator.handle(.cancel)
        await harness.releaseAll()
        let terminal = try await harness.waitForTerminal()
        try await harness.waitForCleanup()

        let events = await harness.capture.events
        #expect(terminal.phase == .cancelled)
        #expect(events == [.prepare, .start, .cancel])
    }

    @Test("Cancelling while recording releases the device without producing a clip")
    func cancelWhileRecording() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        try await harness.startRecording()

        await harness.coordinator.handle(.cancel)
        let terminal = try await harness.waitForTerminal()
        try await harness.waitForCleanup()

        let events = await harness.capture.events
        let discards = await harness.clip.discardCount
        #expect(terminal.phase == .cancelled)
        #expect(events == [.prepare, .start, .cancel])
        #expect(discards == 0)
    }

    @Test("Cancelling twice is idempotent")
    func cancelIsIdempotent() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        try await harness.startRecording()

        await harness.coordinator.handle(.cancel)
        let terminal = try await harness.waitForTerminal()
        try await harness.waitForCleanup()
        await harness.coordinator.handle(.cancel)

        let events = await harness.capture.events
        let repeated = await harness.currentSnapshot()
        let metrics = harness.metrics.all

        #expect(terminal.phase == .cancelled)
        #expect(repeated.phase == .cancelled)
        #expect(events.count(where: { $0 == .cancel }) == 1)
        #expect(metrics.count == 1)
    }

    @Test("Cancelling is answered at once even while an adapter is still working")
    func cancelDoesNotWaitForABusyAdapter() async throws {
        let harness = DictationHarness()
        // Still parked: this adapter does not check for cancellation, which is what a long
        // recognition call on a long recording behaves like.
        await harness.parkOnly(.recognition)
        defer { Task { await harness.releaseAll() } }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }

        await harness.coordinator.handle(.cancel)

        // Answered without waiting for the adapter to return, which could be tens of seconds.
        let cancelled = await harness.currentSnapshot()
        #expect(cancelled.phase == .cancelled)

        // And the user can dictate again immediately, rather than having the activation
        // ignored because the coordinator still thinks it is transcribing.
        try await harness.startRecording()
        let restarted = await harness.currentSnapshot()
        #expect(restarted.phase == .recording)
        #expect(restarted.sessionID != cancelled.sessionID)

        await harness.coordinator.handle(.toggleRecording)
        #expect(try await harness.waitForTerminal().phase == .completed)
    }

    @Test("A cancellation keeps the text the session had already produced")
    func cancelKeepsTheTextAlreadyProduced() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.insertion)
        defer { Task { await harness.releaseAll() } }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("insertion was entered") {
            await harness.inserter.callCount == 1
        }

        await harness.coordinator.handle(.cancel)
        let cancelled = await harness.currentSnapshot()

        // The terminal snapshot is where the user still sees their words. Publishing a bare
        // `.cancelled` would throw away a finished dictation.
        #expect(cancelled.phase == .cancelled)
        #expect(cancelled.transcript.rawText == "raw text")
        #expect(cancelled.transcript.normalizedText == "normalized text")
        #expect(cancelled.transcript.finalText == "refined text")
        #expect(cancelled.context != nil)
    }

    @Test("Cancelling from a finished session does nothing")
    func cancelFromTerminalIsIgnored() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        _ = try await harness.runSession()

        await harness.coordinator.handle(.cancel)
        let snapshot = await harness.currentSnapshot()
        let events = await harness.capture.events

        #expect(snapshot.phase == .completed)
        #expect(events.count(where: { $0 == .cancel }) == 0)
    }

    @Test(
        "An adapter that fails with its own error after a cancellation still ends cancelled",
        arguments: [
            DictationHarness.Boundary.capturePrepare, .captureStart, .captureStop, .recognition,
        ]
    )
    func adapterErrorAfterCancellationEndsCancelled(
        _ boundary: DictationHarness.Boundary
    ) async throws {
        let harness = DictationHarness()
        await harness.parkOnly(boundary)
        defer { Task { await harness.releaseAll() } }

        // An adapter interrupted by a cancellation often reports it as an error of its own
        // rather than `CancellationError`. The user still cancelled; nothing failed.
        switch boundary {
        case .capturePrepare: await harness.capture.setPrepareResponse(.unmappedFailure)
        case .captureStart: await harness.capture.setStartResponse(.unmappedFailure)
        case .captureStop: await harness.capture.setStopResponse(.unmappedFailure)
        case .recognition: await harness.recognizer.setResponse(.unmappedFailure)
        default: Issue.record("No failing response is configured for \(boundary.rawValue)")
        }

        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the session parked at \(boundary.rawValue)") {
            await harness.hasArrived(at: boundary)
        }

        await harness.coordinator.handle(.cancel)
        await harness.releaseAll()
        let terminal = try await harness.waitForTerminal()
        try await harness.waitForCleanup()

        #expect(terminal.phase == .cancelled)
        #expect(terminal.failure == nil)
        #expect(harness.metrics.last?.outcome == .cancelled)
    }
}
