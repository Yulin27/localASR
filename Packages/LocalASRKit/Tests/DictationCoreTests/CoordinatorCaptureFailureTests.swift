import Testing

@testable import DictationCore

@Suite("Capture failures")
struct CoordinatorCaptureFailureTests {
    @Test("A microphone that cannot be prepared fails the session before recording")
    func prepareFailureFailsBeforeRecording() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.capture.setPrepareResponse(
            .failure(
                DictationFailure(
                    stage: .preparing,
                    category: .permissionDenied,
                    recoverability: .recoverable
                )
            )
        )

        let terminal = try await harness.runSessionToTerminal()

        let events = await harness.capture.events
        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.category == .permissionDenied)
        #expect(terminal.failure?.stage == .preparing)
        // Recording never began, so nothing was stopped, and the device was released.
        #expect(events == [.prepare, .cancel])
        #expect(await harness.history.records.isEmpty)
    }

    @Test("A microphone that cannot start fails the session and releases the device")
    func startFailureFailsBeforeRecording() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.capture.setStartResponse(
            .failure(
                DictationFailure(
                    stage: .preparing,
                    category: .deviceUnavailable,
                    recoverability: .recoverable
                )
            )
        )

        let terminal = try await harness.runSessionToTerminal()

        let events = await harness.capture.events
        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.category == .deviceUnavailable)
        #expect(events == [.prepare, .start, .cancel])
    }

    @Test("A capture that cannot be stopped fails at recording and releases the device")
    func stopFailureFailsAtRecording() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        try await harness.startRecording()
        await harness.capture.setStopResponse(
            .failure(
                DictationFailure(
                    stage: .recording,
                    category: .runtimeFailure,
                    recoverability: .recoverable
                )
            )
        )
        await harness.coordinator.handle(.toggleRecording)
        let terminal = try await harness.waitForTerminal()

        let events = await harness.capture.events
        let discards = await harness.clip.discardCount
        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.stage == .recording)
        #expect(events == [.prepare, .start, .stop, .cancel])
        #expect(discards == 0)
    }

    @Test("A failed session can be dismissed and followed by a good one")
    func failureIsRecoverable() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.capture.setStartResponse(
            .failure(
                DictationFailure(
                    stage: .preparing,
                    category: .deviceUnavailable,
                    recoverability: .recoverable
                )
            )
        )

        await harness.coordinator.handle(.toggleRecording)
        let failed = try await harness.waitForTerminal()
        #expect(failed.phase == .failed)

        await harness.coordinator.handle(.dismiss)
        let dismissed = await harness.currentSnapshot()
        #expect(dismissed == .idle)

        await harness.capture.setStartResponse(.ok)
        let recovered = try await harness.runSession()
        #expect(recovered.phase == .completed)
        #expect(recovered.failure == nil)
    }
}
