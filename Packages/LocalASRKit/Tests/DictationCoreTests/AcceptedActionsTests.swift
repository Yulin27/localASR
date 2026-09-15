import Foundation
import Testing

@testable import DictationCore

@Suite("Accepted actions")
struct AcceptedActionsTests {
    private static let startOnly = AcceptedActions(toggle: .start, cancel: false, dismiss: false)
    private static let recording = AcceptedActions(toggle: .stop, cancel: true, dismiss: false)
    private static let processing = AcceptedActions(toggle: .ignored, cancel: true, dismiss: false)
    private static let finished = AcceptedActions(toggle: .start, cancel: false, dismiss: true)

    // MARK: - The value

    @Test("A settled phase accepts what the coordinator accepts there", arguments: DictationPhase.allCases)
    func settledDefaults(_ phase: DictationPhase) {
        let expected: AcceptedActions =
            switch phase {
            case .idle: Self.startOnly
            case .preparing, .recording: Self.recording
            case .transcribing, .normalizing, .refining, .inserting: Self.processing
            case .completed, .cancelled, .failed: Self.finished
            }
        #expect(AcceptedActions(settledIn: phase) == expected)
        #expect(SessionSnapshot(phase: phase).acceptedActions == expected)
    }

    @Test("Accepting an action means it would change something")
    func acceptsMatchesTheFields() {
        #expect(Self.processing.accepts(.toggleRecording) == false)
        #expect(Self.processing.accepts(.cancel))
        #expect(Self.processing.accepts(.dismiss) == false)
        #expect(Self.finished.accepts(.toggleRecording))
        #expect(Self.finished.accepts(.dismiss))
        #expect(DictationAction.allCases.allSatisfy { !AcceptedActions.nothing.accepts($0) })
    }

    // MARK: - Published by the coordinator

    @Test("Idle accepts only a start")
    func idleAcceptsStart() async {
        let harness = DictationHarness()
        #expect(await harness.currentSnapshot().acceptedActions == Self.startOnly)
    }

    @Test("Preparing and recording accept a stop and a cancel")
    func preparingAndRecordingAcceptStop() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.capturePrepare)
        defer { Task { await harness.releaseAll() } }

        await harness.coordinator.handle(.toggleRecording)
        let preparing = try await harness.waitForPhase(.preparing)
        #expect(preparing.acceptedActions == Self.recording)

        await harness.releaseAll()
        let recording = try await harness.waitForPhase(.recording)
        #expect(recording.acceptedActions == Self.recording)
    }

    @Test(
        "Every processing phase accepts a cancel and ignores an activation",
        arguments: [
            (DictationHarness.Boundary.recognition, DictationPhase.transcribing),
            (.deterministic, .normalizing),
            (.refinement, .refining),
            (.insertion, .inserting),
        ]
    )
    func processingPhasesAcceptCancel(
        _ boundary: DictationHarness.Boundary,
        _ phase: DictationPhase
    ) async throws {
        let harness = DictationHarness()
        await harness.parkOnly(boundary)
        defer { Task { await harness.releaseAll() } }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the session parked at \(boundary)") {
            await harness.hasArrived(at: boundary)
        }

        let parked = await harness.currentSnapshot()
        #expect(parked.phase == phase)
        #expect(parked.acceptedActions == Self.processing)
    }

    @Test("A completed or failed session accepts a start and a dismiss")
    func finishedSessionsAcceptStartAndDismiss() async throws {
        let completed = DictationHarness()
        await completed.allowAll()
        let done = try await completed.runSession()
        #expect(done.phase == .completed)
        #expect(done.acceptedActions == Self.finished)

        let failed = DictationHarness()
        await failed.allowAll()
        await failed.recognizer.setResponse(
            .failure(
                DictationFailure(
                    stage: .transcribing,
                    category: .runtimeFailure,
                    recoverability: .recoverable
                )
            )
        )
        let failure = try await failed.runSession()
        #expect(failure.phase == .failed)
        #expect(failure.acceptedActions == Self.finished)
    }

    @Test("Dismissing returns to a snapshot that accepts only a start")
    func dismissedAcceptsStart() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        _ = try await harness.runSession()

        await harness.coordinator.handle(.dismiss)
        #expect(await harness.currentSnapshot().acceptedActions == Self.startOnly)
    }

    // MARK: - Where state and phase diverge

    @Test("A finished session still cleaning up says so without changing its phase")
    func cleanupWindowIsPublished() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        let write = Latch()
        await harness.history.setWriteGate(write)
        defer { Task { await write.open() } }

        let stream = await harness.coordinator.snapshots()
        let collector = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
            }
            return snapshots
        }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the history write was entered") {
            await harness.history.attempts == 1
        }

        // The coordinator has let the session go, so an activation would start a new one. The
        // phase still reads `.inserting`, because the terminal phase follows the history write.
        let parked = await harness.currentSnapshot()
        #expect(parked.phase == .inserting)
        #expect(parked.acceptedActions == Self.startOnly)

        await write.open()
        let terminal = try await harness.waitForTerminal()
        #expect(terminal.phase == .completed)
        #expect(terminal.acceptedActions == Self.finished)

        await harness.coordinator.shutdown()
        let observed = await collector.value
        let inserting = observed.filter { $0.phase == .inserting }

        // Exactly one refresh, identical to the snapshot before it except for the actions, and
        // followed by the terminal snapshot.
        try #require(inserting.count == 2)
        #expect(inserting[0].acceptedActions == Self.processing)
        #expect(inserting[1] == inserting[0].accepting(Self.startOnly))
        #expect(observed.map(\.phase).suffix(3) == [.inserting, .inserting, .completed])
    }

    @Test("A cancellation publishes actions for a coordinator with nothing in flight")
    func cancellationPublishesNothingInFlight() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        // Recognition runs on past the cancellation, so the abandoned run is still unwinding.
        let recognition = Gate()
        await harness.recognizer.setGate(recognition)
        defer { Task { await recognition.open() } }

        try await harness.startRecording()
        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("recognition was entered") {
            await harness.recognizer.callCount == 1
        }

        await harness.coordinator.handle(.cancel)
        let cancelled = await harness.currentSnapshot()
        #expect(cancelled.phase == .cancelled)
        #expect(cancelled.acceptedActions == Self.finished)

        // And the claim holds: the activation it offers really starts a session.
        try await harness.startRecording()
        #expect(await harness.currentSnapshot().sessionID != cancelled.sessionID)
        await harness.coordinator.handle(.cancel)
    }

    @Test("A session cancelled before it was shown publishes the same actions")
    func preFreezeCancellationPublishesNothingInFlight() async throws {
        let harness = DictationHarness()
        await harness.parkOnly(.targetCapture)
        defer { Task { await harness.releaseAll() } }

        await harness.coordinator.handle(.toggleRecording)
        try await harness.waitUntil("the session parked at target capture") {
            await harness.targetProvider.callCount > 0
        }

        // The pre-freeze window: nothing may be published for this session, so the snapshot
        // still offers the start that began it. The coordinator decides the next action
        // against the session actually in flight.
        let stale = await harness.currentSnapshot()
        #expect(stale.phase == .idle)
        #expect(stale.acceptedActions == Self.startOnly)

        await harness.coordinator.handle(.cancel)
        let cancelled = await harness.currentSnapshot()
        #expect(cancelled.phase == .cancelled)
        #expect(cancelled.acceptedActions == Self.finished)
    }

    @Test("A coordinator that was shut down accepts nothing")
    func shutDownAcceptsNothing() async {
        let harness = DictationHarness()
        await harness.coordinator.shutdown()
        #expect(await harness.currentSnapshot().acceptedActions == .nothing)
    }
}
