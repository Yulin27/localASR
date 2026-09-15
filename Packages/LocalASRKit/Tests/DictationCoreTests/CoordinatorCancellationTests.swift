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
            // Capture already handed over a clip, so the device is not released again.
            #expect(events.count(where: { $0 == .cancel }) == 0)
            #expect(discards == 1)
        } else if boundary.hasClaimedDevice {
            // The session holds the microphone and produced no clip, so it must release it.
            #expect(events.count(where: { $0 == .cancel }) == 1)
            #expect(events.count(where: { $0 == .stop }) == 0)
            #expect(discards == 0)
        } else {
            // Cancelled before the microphone was ever claimed. Releasing one this session
            // never took would land on whichever session picks it up next.
            #expect(events.isEmpty, "capture events were \(events)")
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

    @Test("A cancellation during insertion still reports what happened to the text")
    func cancelDuringInsertionKeepsTheOutcome() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.insertion)

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("insertion was entered") {
            await harness.inserter.callCount == 1
        }

        await harness.coordinator.handle(.cancel)
        // Answered before the inserter came back, so it cannot know the outcome yet.
        #expect(await harness.currentSnapshot().insertion == nil)

        await harness.releaseAll()
        try await harness.waitForCleanup()

        // The delivery went ahead regardless, and the user needs to know whether their text
        // landed in the document, went to the clipboard, or failed.
        let terminal = await harness.currentSnapshot()
        #expect(terminal.phase == .cancelled)
        #expect(terminal.insertion?.delivery == .insertedDirectly)
        #expect(terminal.transcript.finalText == "refined text")
    }

    @Test("A stop already buffered does not survive a cancellation")
    func bufferedStopDoesNotSurviveCancellation() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        try await harness.startRecording()

        // The user presses to stop and then changes their mind. The stop is already in the
        // buffer, and a finished signal still delivers what it holds, so reaching the stop
        // wait proves nothing about whether the session is still wanted.
        await harness.coordinator.handle(.toggleRecording)
        await harness.coordinator.handle(.cancel)
        try await harness.waitForCleanup()

        // Stopping would have turned a cancelled recording into a clip.
        #expect(await harness.capture.events == [.prepare, .start, .cancel])
        #expect(await harness.clip.discardCount == 0)
    }

    @Test("A cancelled stage is measured to the cancellation, not to the adapter's return")
    func cancelledStageIsMeasuredToTheCancellation() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.recognition)

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }

        await harness.coordinator.handle(.cancel)

        // The adapter keeps running long after the user gave up: time passes, and none of it
        // is time they spent waiting for a session they had already cancelled.
        for _ in 0..<20 {
            _ = harness.time.now()
        }
        await harness.releaseAll()
        try await harness.waitForCleanup()

        let metrics = try #require(harness.metrics.last)
        let transcribing = try #require(metrics.timings.last)
        #expect(metrics.outcome == .cancelled)
        #expect(transcribing.phase == .transcribing)
        // One tick: entering `transcribing`, then the cancellation. Billing the overrun here
        // would make a stage that the user experienced as instant look like a stall.
        #expect(transcribing.duration == FakeTimeSource.step)
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

    @Test("A session cancelled before it was ever shown does not inherit the last one's text")
    func cancelBeforeFirstPublicationDoesNotInheritTheLastSession() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        let previous = try await harness.runSession()
        #expect(previous.transcript.finalText == "refined text")

        // Parked before the destination is frozen, which is before anything is published.
        await harness.parkOnly(.targetCapture)
        defer { Task { await harness.releaseAll() } }
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the second session parked at target capture") {
            await harness.targetProvider.callCount == 2
        }

        // Still showing the finished session, because this one has published nothing.
        #expect(await harness.currentSnapshot().sessionID == previous.sessionID)

        await harness.coordinator.handle(.cancel)
        let cancelled = await harness.currentSnapshot()

        #expect(cancelled.phase == .cancelled)
        #expect(cancelled.sessionID != previous.sessionID)
        // Carrying the previous session's text into this one's terminal state would show the
        // user a result they did not just dictate.
        #expect(cancelled.transcript == .empty)
        #expect(cancelled.context == nil)
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
