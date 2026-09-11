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

        let events = await harness.capture.events
        let discards = await harness.clip.discardCount
        let metrics = harness.metrics.all

        #expect(terminal.phase == .cancelled)
        #expect(metrics.count == 1)
        #expect(metrics.last?.outcome == .cancelled)

        if boundary == .insertion {
            // The text had already been handed to the inserter, so history keeps it: the
            // session was cancelled, but the text may well be in the user's document. The
            // record is written after the terminal snapshot, so wait for it instead of reading
            // once. The fake store honours cancellation, as a real one would.
            try await harness.waitUntil("history recorded the cancelled session") {
                await harness.history.records.count == 1
            }
            #expect(terminal.insertion != nil)
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
        await harness.coordinator.handle(.cancel)

        let events = await harness.capture.events
        let repeated = await harness.currentSnapshot()
        let metrics = harness.metrics.all

        #expect(terminal.phase == .cancelled)
        #expect(repeated.phase == .cancelled)
        #expect(events.count(where: { $0 == .cancel }) == 1)
        #expect(metrics.count == 1)
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

        #expect(terminal.phase == .cancelled)
        #expect(terminal.failure == nil)
        #expect(harness.metrics.last?.outcome == .cancelled)
    }

    @Test("Cancelling does not wait for an adapter that ignores the cancellation")
    func cancelDoesNotWaitForAnUncooperativeAdapter() async throws {
        let harness = DictationHarness(ignoringCancellationAt: [.recognition])
        await harness.parkOnly(.recognition)
        defer { Task { await harness.releaseAll() } }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }
        let abandoned = await harness.currentSnapshot().sessionID

        // The recognizer stays parked through the cancellation, like a long model call that
        // never checks for it. The user should not have to wait for that call to return.
        await harness.coordinator.handle(.cancel)
        let cancelled = try await harness.waitForPhase(.cancelled)
        #expect(cancelled.sessionID == abandoned)

        try await harness.startRecording()
        let next = await harness.currentSnapshot()
        #expect(next.sessionID != abandoned)

        // When the abandoned call finally returns, it must not disturb the new session.
        await harness.releaseAll()
        try await harness.waitUntil("the abandoned session released its clip") {
            await harness.clip.discardCount == 1
        }
        let afterRelease = await harness.currentSnapshot()
        #expect(afterRelease.phase == .recording)
        #expect(afterRelease.sessionID == next.sessionID)

        await harness.coordinator.handle(.cancel)
        #expect(try await harness.waitForTerminal().phase == .cancelled)
    }
}
