import Foundation
import Synchronization

@testable import DictationCore

/// Wires the fakes to a coordinator, and provides deterministic waiting.
///
/// Every port is a fake and the clock is injected, so a session runs end to end with no
/// microphone, no Accessibility permission, no network, and no model.
///
/// `Sendable` because every stored property is an actor or an immutable value, which lets a
/// test hand the harness to a teardown task that releases parked ports.
final class DictationHarness: Sendable {
    /// An await boundary a test can park a session on.
    enum Boundary: String, CaseIterable, Sendable {
        case targetCapture
        case settings
        case capturePrepare
        case captureStart
        case captureStop
        case voiceActivity
        case recognition
        case deterministic
        case refinement
        case insertion
    }

    enum HarnessError: Error, CustomStringConvertible {
        case timedOut(DictationPhase)
        case conditionNeverHeld(String)

        var description: String {
            switch self {
            case .timedOut(let phase):
                "Timed out waiting for the session to reach \(phase)"
            case .conditionNeverHeld(let condition):
                "Timed out waiting until \(condition)"
            }
        }
    }

    let clip: FakeAudioClip
    let capture: FakeAudioCapturing
    let voiceActivity: FakeVoiceActivityDetector
    let recognizer: FakeSpeechRecognizer
    let processor: FakeTextProcessor
    let refiner: FakeRefiner
    let inserter: FakeInserter
    let targetProvider: FakeTargetProvider
    let modeResolver: FakeModeResolver
    let settingsProvider: FakeSettingsProvider
    let history: FakeHistoryStore
    let metrics: FakeMetricsRecorder
    let time: FakeTimeSource
    let coordinator: DictationCoordinator

    private let latches: [Boundary: Latch]

    /// `ignoringCancellationAt` lists the boundaries whose port call keeps running when the
    /// session is cancelled, the way an adapter that never checks for cancellation does. A
    /// session parked at one of them stays parked until ``releaseAll()``.
    init(
        settings: DictationSettings = .standard,
        target: TargetCaptureResult? = nil,
        modeBindings: [String: RefinementMode] = [:],
        refinementGuard: RefinementOutputGuard = RefinementOutputGuard(),
        ignoringCancellationAt uncooperative: Set<Boundary> = []
    ) {
        let latches = Dictionary(
            uniqueKeysWithValues: Boundary.allCases.map {
                ($0, Latch(opensOnCancel: !uncooperative.contains($0)))
            }
        )
        self.latches = latches

        clip = FakeAudioClip()
        capture = FakeAudioCapturing(
            clip: clip,
            prepareLatch: latches[.capturePrepare],
            startLatch: latches[.captureStart],
            stopLatch: latches[.captureStop]
        )
        voiceActivity = FakeVoiceActivityDetector(latch: latches[.voiceActivity])
        recognizer = FakeSpeechRecognizer(latch: latches[.recognition])
        processor = FakeTextProcessor(latch: latches[.deterministic])
        refiner = FakeRefiner(latch: latches[.refinement])
        inserter = FakeInserter(latch: latches[.insertion])
        targetProvider = FakeTargetProvider(
            result: target ?? FakeTargetProvider.defaultResult,
            latch: latches[.targetCapture]
        )
        modeResolver = FakeModeResolver(modes: modeBindings)
        settingsProvider = FakeSettingsProvider(settings: settings, latch: latches[.settings])
        history = FakeHistoryStore()
        metrics = FakeMetricsRecorder()
        time = FakeTimeSource()

        let sequence = SessionIDSequence()
        coordinator = DictationCoordinator(
            dependencies: DictationCoordinator.Dependencies(
                capture: capture,
                voiceActivity: voiceActivity,
                recognition: recognizer,
                textProcessing: processor,
                refiner: refiner,
                inserter: inserter,
                targetProvider: targetProvider,
                modeResolver: modeResolver,
                settings: settingsProvider,
                history: history,
                metrics: metrics,
                time: time
            ),
            sessionIDs: SessionIDGenerator { sequence.next() },
            refinementGuard: refinementGuard
        )
    }

    // MARK: - Latch control

    /// Lets every port call through. Call before any ordinary run.
    func allowAll() async {
        for latch in latches.values {
            await latch.open()
        }
    }

    /// Lets every port call through except `boundary`, which parks the session.
    func parkOnly(_ boundary: Boundary) async {
        for (key, latch) in latches {
            if key == boundary {
                await latch.close()
            } else {
                await latch.open()
            }
        }
    }

    /// Releases every parked call. Idempotent, and safe to call from a teardown path.
    func releaseAll() async {
        await allowAll()
    }

    // MARK: - Driving

    /// Presses the shortcut and waits until recording has actually begun.
    func startRecording() async throws {
        await coordinator.handle(.toggleRecording)
        _ = try await waitForPhase(.recording)
    }

    /// A complete press, record, press cycle.
    @discardableResult
    func runSession() async throws -> SessionSnapshot {
        try await startRecording()
        await coordinator.handle(.toggleRecording)
        return try await waitForTerminal()
    }

    /// One press and straight to a terminal state, for paths that fail during preparation.
    @discardableResult
    func runSessionToTerminal() async throws -> SessionSnapshot {
        await coordinator.handle(.toggleRecording)
        return try await waitForTerminal()
    }

    // MARK: - Waiting

    /// Waits until the session reaches `phase`.
    ///
    /// Bounded and loud: a session parked on a latch fails the test with a message instead of
    /// hanging on a continuation nobody resumes.
    @discardableResult
    func waitForPhase(_ phase: DictationPhase, attempts: Int = 20_000) async throws -> SessionSnapshot {
        for _ in 0..<attempts {
            let snapshot = await coordinator.currentSnapshot()
            if snapshot.phase == phase { return snapshot }
            await Task.yield()
        }
        throw HarnessError.timedOut(phase)
    }

    @discardableResult
    func waitForTerminal(attempts: Int = 20_000) async throws -> SessionSnapshot {
        for _ in 0..<attempts {
            let snapshot = await coordinator.currentSnapshot()
            if snapshot.phase.isTerminal { return snapshot }
            await Task.yield()
        }
        throw HarnessError.timedOut(.completed)
    }

    /// Spins until `condition` holds. Same bounded-and-loud contract as ``waitForPhase(_:)``.
    func waitUntil(
        _ description: String,
        attempts: Int = 20_000,
        _ condition: () async -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if await condition() { return }
            await Task.yield()
        }
        throw HarnessError.conditionNeverHeld(description)
    }

    /// Spins a bounded number of times and reports whether `condition` ever held.
    ///
    /// For asserting that something does not happen. A correct coordinator spends the whole
    /// budget; a broken one satisfies the condition within a few hops.
    func eventually(attempts: Int = 2_000, _ condition: () async -> Bool) async -> Bool {
        for _ in 0..<attempts {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    func currentSnapshot() async -> SessionSnapshot {
        await coordinator.currentSnapshot()
    }

    /// Whether the session has reached a boundary and is now parked there.
    func hasArrived(at boundary: Boundary) async -> Bool {
        switch boundary {
        case .targetCapture: await targetProvider.callCount > 0
        case .settings: await settingsProvider.callCount > 0
        case .capturePrepare: await capture.events.contains(.prepare)
        case .captureStart: await capture.events.contains(.start)
        case .captureStop: await capture.events.contains(.stop)
        case .voiceActivity: await voiceActivity.callCount > 0
        case .recognition: await recognizer.callCount > 0
        case .deterministic: await processor.callCount > 0
        case .refinement: await refiner.callCount > 0
        case .insertion: await inserter.callCount > 0
        }
    }
}

extension DictationHarness.Boundary {
    /// Whether capture has already produced a clip by the time a session reaches this
    /// boundary. Until it has, cancelling a session must also release the device.
    var isAfterCaptureStop: Bool {
        switch self {
        case .targetCapture, .settings, .capturePrepare, .captureStart: false
        case .captureStop, .voiceActivity, .recognition, .deterministic, .refinement, .insertion: true
        }
    }

    /// Whether a session reaches this boundary before it asks the device to start. A session
    /// cancelled here must never start recording.
    var isBeforeCaptureStart: Bool {
        switch self {
        case .targetCapture, .settings, .capturePrepare: true
        case .captureStart, .captureStop, .voiceActivity, .recognition, .deterministic, .refinement, .insertion: false
        }
    }
}

/// Hands out predictable session identifiers.
///
/// A deterministic generator keeps assertions readable; the coordinator's generation counter
/// is what actually rejects a superseded session, including one whose generator repeats an ID.
final class SessionIDSequence: Sendable {
    private let counter = Mutex<Int>(0)

    func next() -> SessionID {
        let value = counter.withLock { value -> Int in
            value += 1
            return value
        }
        let suffix = String(format: "%012d", value)
        guard let uuid = UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") else {
            preconditionFailure("SessionIDSequence produced a malformed UUID suffix: \(suffix)")
        }
        return SessionID(rawValue: uuid)
    }
}

extension FakeTargetProvider {
    /// The destination the fake reports unless a test overrides it.
    static var defaultResult: TargetCaptureResult {
        .captured(
            InsertionTarget(
                application: ActiveApplication(
                    processIdentifier: 501,
                    bundleIdentifier: "com.example.editor",
                    localizedName: "Editor"
                ),
                elementToken: "focused-field"
            )
        )
    }
}
