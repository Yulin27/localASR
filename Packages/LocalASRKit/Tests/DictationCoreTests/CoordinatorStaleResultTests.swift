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

    @Test("A new session waits for the previous one to finish releasing the microphone")
    func newSessionWaitsForTheDeviceRelease() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        try await harness.startRecording()

        // Held open so the release is still running when the next session starts. The release
        // deliberately runs outside the session's cancellation, so nothing but this wait
        // orders it against a `prepare()` the user triggers a moment later.
        let deviceRelease = Latch()
        await harness.capture.setCancelGate(deviceRelease)

        await harness.coordinator.handle(.cancel)
        try await harness.waitUntil("the device release was entered") {
            await harness.capture.events.contains(.cancel)
        }

        // The user starts dictating again while the microphone is still being released.
        await harness.coordinator.handle(.toggleRecording)

        // It must not reach `.recording` while the release is in flight. Doing so would put
        // a live recording and an outstanding `cancel()` on the same device, and the release
        // would shut down a session that has nothing to do with it.
        #expect(await harness.expectNeverReaches(.recording))
        #expect(await harness.capture.completedCancels == 0)

        await deviceRelease.open()
        _ = try await harness.waitForPhase(.recording)

        // The release finished before the new session started recording, not alongside it.
        #expect(await harness.capture.completedCancels == 1)
        #expect(await harness.capture.events == [.prepare, .start, .cancel, .prepare, .start])
    }

    @Test("A new session waits out a capture call the cancelled one left running")
    func newSessionWaitsForCaptureThatIgnoredCancellation() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        // `start()` keeps running after the cancellation, as a device call already in flight
        // does. Cancelling the task does not reach into it.
        let startCall = Gate()
        await harness.capture.setStartGate(startCall)
        defer { Task { await startCall.open() } }

        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("capture.start was entered") {
            await harness.capture.events.contains(.start)
        }

        await harness.coordinator.handle(.cancel)
        #expect(await harness.currentSnapshot().phase == .cancelled)

        // The user dictates again while the abandoned session is still inside `start()`.
        await harness.coordinator.handle(.toggleRecording)

        // It must not touch the device yet. Two sessions driving one microphone is how an
        // old `start()` or `stop()` ends up stopping the new recording.
        #expect(await harness.expectNeverReaches(.recording))
        #expect(await harness.capture.events.count(where: { $0 == .prepare }) == 1)

        await startCall.open()
        _ = try await harness.waitForPhase(.recording)

        // The abandoned session finished with the device — including releasing it — before
        // the new one prepared.
        #expect(await harness.capture.completedCancels == 1)
        #expect(await harness.capture.events == [.prepare, .start, .cancel, .prepare, .start])
    }

    @Test("The microphone is handed over as soon as the clip is in hand, not after cleanup")
    func captureIsHandedOverBeforeTheRestOfCleanup() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        // `stop()` keeps running after the cancellation and still returns a clip; disposing
        // of that clip is then slow, as a disk-backed recording's would be.
        let stopCall = Gate()
        let discard = Gate()
        await harness.capture.setStopGate(stopCall)
        await harness.clip.setDiscardGate(discard)
        defer {
            Task {
                await stopCall.open()
                await discard.open()
            }
        }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("capture.stop was entered") {
            await harness.capture.events.contains(.stop)
        }

        await harness.coordinator.handle(.cancel)
        await harness.coordinator.handle(.toggleRecording)

        // The old `stop()` is still in flight, so the device is not free yet.
        #expect(await harness.expectNeverReaches(.recording))

        await stopCall.open()

        // The clip is in hand, so the microphone is free and the next session records —
        // while the abandoned one is still parked disposing of that clip. Waiting for
        // disposal would make the next dictation hostage to a slow disk.
        _ = try await harness.waitForPhase(.recording)
        try await harness.waitUntil("the abandoned clip's disposal was entered") {
            await harness.clip.discardCount == 1
        }
        #expect(await harness.currentSnapshot().phase == .recording)

        // No `cancel`: the abandoned session handed over a clip rather than a live device,
        // so it had nothing to release.
        #expect(await harness.capture.events == [.prepare, .start, .stop, .prepare, .start])
    }

    @Test("A session cancelled while waiting for the microphone stops waiting")
    func cancelledWaiterDoesNotQueueBehindTheNextRecording() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        // The first session holds the device inside a `start()` that ignores cancellation.
        let startCall = Gate()
        await harness.capture.setStartGate(startCall)
        defer { Task { await startCall.open() } }

        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("capture.start was entered") {
            await harness.capture.events.contains(.start)
        }
        await harness.coordinator.handle(.cancel)

        // A second session starts and parks waiting for that device, then is cancelled too.
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the second session captured its destination") {
            await harness.targetProvider.callCount == 2
        }
        await harness.coordinator.handle(.cancel)

        // It must unwind now, on its own cancellation. Queueing behind the microphone would
        // leave it holding its cleanup and its metrics until whoever records next stops —
        // which is up to the user, and may be never.
        try await harness.waitForCleanup()
        #expect(harness.metrics.last?.outcome == .cancelled)
        // The first session is still inside `start()`, so this can only be the second.
        #expect(harness.metrics.all.count == 1)

        // A third session waits properly, and gets the device once the first lets go.
        await harness.coordinator.handle(.toggleRecording)
        #expect(await harness.expectNeverReaches(.recording))
        await startCall.open()
        _ = try await harness.waitForPhase(.recording)
    }

    @Test("A session still cleaning up does not stop the user from dictating again")
    func slowCleanupDoesNotBlockTheNextSession() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        // A store doing slow I/O. The session is over by the time this runs, so it must not
        // hold the coordinator.
        let write = Latch()
        await harness.history.setWriteGate(write)
        defer { Task { await write.open() } }

        try await harness.startRecording()
        let first = try #require(await harness.currentSnapshot().sessionID)
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the history write was entered") {
            await harness.history.attempts == 1
        }

        // Parked mid-cleanup: the phase still reads `.inserting` although nothing is left to
        // stop, which is exactly the state a phase-driven toggle would refuse to act on.
        #expect(await harness.currentSnapshot().phase == .inserting)

        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitForPhase(.recording)
        let second = try #require(await harness.currentSnapshot().sessionID)
        #expect(second != first)

        // The first session's cleanup finishes underneath the new one and must not publish
        // its own terminal state over it.
        await write.open()
        try await harness.waitUntil("the first session's record was written") {
            await harness.history.records.count == 1
        }
        #expect(await harness.currentSnapshot().phase == .recording)
        #expect(await harness.currentSnapshot().sessionID == second)
    }

    @Test("A transcript produced after a cancellation never reaches the user")
    func lateTranscriptDoesNotReachTheCancelledSnapshot() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        // The recogniser runs on past the cancellation and returns a perfectly good result.
        let recognition = Gate()
        await harness.recognizer.setGate(recognition)
        defer { Task { await recognition.open() } }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }

        await harness.coordinator.handle(.cancel)
        await recognition.open()
        try await harness.waitForCleanup()

        // The terminal snapshot outlives the cancellation now, so it has to show what the
        // session had when the user gave up on it — not words that arrived afterwards.
        let terminal = await harness.currentSnapshot()
        #expect(terminal.phase == .cancelled)
        #expect(terminal.transcript == .empty)
        #expect(harness.metrics.last?.rawCharacterCount == nil)
        #expect(await harness.processor.callCount == 0)
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
