import Testing

@testable import DictationCore

@Suite("Stale results and superseded sessions")
struct CoordinatorStaleResultTests {
    @Test("An adapter that ignores cancellation cannot advance a cancelled session")
    func lateResultFromAnAdapterThatIgnoresCancellation() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.recognition)

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }

        await harness.coordinator.handle(.cancel)

        // Released *after* the cancellation, and the fake does not check for cancellation, so
        // it returns a perfectly good result — exactly what an adapter that ignores the
        // cancellation does in the real application.
        await harness.releaseAll()

        let terminal = try await harness.waitForTerminal()
        try await harness.waitForCleanup()
        let processed = await harness.processor.callCount
        let refined = await harness.refiner.callCount
        let inserted = await harness.inserter.callCount
        let metrics = harness.metrics.all
        let records = await harness.history.records

        #expect(terminal.phase == .cancelled)
        // The late result must not carry the pipeline forward.
        #expect(processed == 0)
        #expect(refined == 0)
        #expect(inserted == 0)
        #expect(metrics.count == 1)
        #expect(metrics.last?.outcome == .cancelled)
        #expect(records.isEmpty)
    }

    @Test("A session abandoned mid-pipeline does not disturb the one after it")
    func abandonedSessionDoesNotDisturbTheNext() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.recognition)

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }

        let abandoned = try #require(await harness.currentSnapshot().sessionID)
        await harness.coordinator.handle(.cancel)
        await harness.releaseAll()
        let cancelled = try await harness.waitForTerminal()
        // Waited out here so the two sessions' metrics are recorded in a defined order; the
        // coordinator does not otherwise order an abandoned run against the next session.
        try await harness.waitForCleanup()
        #expect(cancelled.phase == .cancelled)

        // The next session runs normally, and owns the published state.
        await harness.allowAll()
        let next = try await harness.runSession()
        let nextID = try #require(next.sessionID)

        #expect(nextID != abandoned)
        #expect(next.phase == .completed)
        #expect(next.transcript.finalText == "refined text")
        #expect(next.failure == nil)

        // Only the completed session produced history; the abandoned one produced metrics only.
        try await harness.waitUntil("history recorded the completed session") {
            await harness.history.records.count == 1
        }
        let records = await harness.history.records
        #expect(records.first?.sessionID == nextID)
        #expect(harness.metrics.all.map(\.outcome) == [.cancelled, .completed])
    }

    @Test("A clip is discarded exactly once even when its session is abandoned")
    func abandonedClipIsDiscarded() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.refinement)

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("refinement was entered") {
            await harness.refiner.callCount == 1
        }

        await harness.coordinator.handle(.cancel)
        await harness.releaseAll()
        let terminal = try await harness.waitForTerminal()
        try await harness.waitForCleanup()

        let discards = await harness.clip.discardCount
        let inserted = await harness.inserter.callCount
        #expect(terminal.phase == .cancelled)
        #expect(discards == 1)
        #expect(inserted == 0)
    }
}
