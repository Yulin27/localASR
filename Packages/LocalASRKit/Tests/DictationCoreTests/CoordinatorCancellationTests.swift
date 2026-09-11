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
        let records = await harness.history.records

        #expect(terminal.phase == .cancelled)
        #expect(metrics.count == 1)
        #expect(metrics.last?.outcome == .cancelled)

        if boundary == .insertion {
            // The text had already been handed to the inserter, so history keeps it: the
            // session was cancelled, but the text may well be in the user's document.
            #expect(records.count == 1)
            #expect(terminal.insertion != nil)
        } else {
            #expect(records.isEmpty)
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
}
