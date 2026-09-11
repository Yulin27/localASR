import Foundation

/// Ends a recording session.
enum StopSignal: Sendable {
    /// The user activated the shortcut a second time.
    case stop
}

/// Owns the dictation workflow, and is the only place a session's phase changes.
///
/// UI and adapters report inputs and results; they never orchestrate. Every phase change goes
/// through one of the private `advance` or `publish` paths here, which validate the transition
/// table and reject anything belonging to a superseded session.
public actor DictationCoordinator {
    /// The capabilities a coordinator needs, wired once at the composition root.
    ///
    /// This is a parameter object, not a locator: the coordinator reads only these fields and
    /// nothing resolves anything at runtime.
    public struct Dependencies: Sendable {
        public var capture: any AudioCapturing
        public var voiceActivity: any VoiceActivityDetecting
        public var recognition: any SpeechRecognizing
        public var textProcessing: any DeterministicTextProcessing
        public var refiner: any TextRefining
        public var inserter: any TextInserting
        public var targetProvider: any ActiveApplicationProviding
        public var modeResolver: any ModeResolving
        public var settings: any DictationSettingsProviding
        public var history: any HistoryStoring
        public var metrics: any MetricsRecording
        public var time: any TimeSource

        public init(
            capture: any AudioCapturing,
            voiceActivity: any VoiceActivityDetecting,
            recognition: any SpeechRecognizing,
            textProcessing: any DeterministicTextProcessing,
            refiner: any TextRefining,
            inserter: any TextInserting,
            targetProvider: any ActiveApplicationProviding,
            modeResolver: any ModeResolving,
            settings: any DictationSettingsProviding,
            history: any HistoryStoring,
            metrics: any MetricsRecording,
            time: any TimeSource
        ) {
            self.capture = capture
            self.voiceActivity = voiceActivity
            self.recognition = recognition
            self.textProcessing = textProcessing
            self.refiner = refiner
            self.inserter = inserter
            self.targetProvider = targetProvider
            self.modeResolver = modeResolver
            self.settings = settings
            self.history = history
            self.metrics = metrics
            self.time = time
        }
    }

    /// The session currently owned by the coordinator.
    private struct ActiveSession {
        let id: SessionID
        let generation: UInt64
        let task: Task<Void, Never>
    }

    /// Everything one session accumulates while it runs.
    ///
    /// Private to the actor, so it can hold the clip: the clip never reaches a snapshot, and
    /// it is released in `finalize` on every path, including the ones where the session was
    /// superseded.
    private struct SessionRun {
        let id: SessionID
        let generation: UInt64
        /// The moment the shortcut was pressed. Also the context's start time, so the clock is
        /// read once per phase boundary and stage timings stay exact.
        let startedAt: Timestamp
        var context: SessionContext?
        var clip: (any AudioClip)?
        var transcript: Transcript = .empty
        var refinement: RefinementSummary?
        var insertion: InsertionOutcome?
        var recognitionEngine: EngineIdentifier?
        var refinementEngine: EngineIdentifier?
        var fallbacks: [FallbackReason] = []
        var timings: [StageTiming] = []
        var phaseEnteredAt: Timestamp
        var failure: DictationFailure?
        var outcome: SessionMetrics.Outcome = .failed

        var terminalPhase: DictationPhase {
            switch outcome {
            case .completed: .completed
            case .cancelled: .cancelled
            case .failed: .failed
            }
        }
    }

    private let dependencies: Dependencies
    private let sessionIDs: SessionIDGenerator
    private let guardRail: RefinementOutputGuard

    private var snapshot: SessionSnapshot = .idle
    private var active: ActiveSession?
    private var stopSignal: AsyncStream<StopSignal>.Continuation?
    private var generation: UInt64 = 0
    private var subscribers: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]
    private var isShutDown = false

    public init(
        dependencies: Dependencies,
        sessionIDs: SessionIDGenerator = .random,
        refinementGuard: RefinementOutputGuard = RefinementOutputGuard()
    ) {
        self.dependencies = dependencies
        self.sessionIDs = sessionIDs
        self.guardRail = refinementGuard
    }

    // MARK: - Public interface

    /// Forwards a semantic user action.
    ///
    /// Synchronous on purpose: it mutates coordinator state and returns, while the pipeline
    /// runs in a task of its own. That is what lets a cancellation, or a second activation,
    /// arrive while a long recognition call is still in flight.
    public func handle(_ action: DictationAction) {
        switch action {
        case .toggleRecording: toggle()
        case .cancel: cancelActiveSession()
        case .dismiss: dismiss()
        }
    }

    /// The current state, for a caller that renders on demand.
    public func currentSnapshot() -> SessionSnapshot { snapshot }

    /// An asynchronous view of every state change, starting with the current state.
    ///
    /// Each call returns a stream of its own, so several views can observe independently, and
    /// the current snapshot is delivered on subscribe so a late observer never renders a stale
    /// state.
    ///
    /// The buffer is unbounded on purpose. Dropping to the newest snapshot would be fine for
    /// rendering, but it would make a subscriber unable to observe the sequence of phases —
    /// and a session produces only a handful of snapshots holding small values, so there is
    /// nothing to protect against.
    public func snapshots() -> AsyncStream<SessionSnapshot> {
        let token = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: SessionSnapshot.self,
            bufferingPolicy: .unbounded
        )
        continuation.yield(snapshot)

        guard !isShutDown else {
            continuation.finish()
            return stream
        }

        subscribers[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(token) }
        }
        return stream
    }

    /// Ends every stream and abandons any active session.
    ///
    /// Termination is explicit rather than tied to deinitialization: an actor's `deinit` runs
    /// outside its isolation and cannot touch `subscribers`.
    public func shutdown() {
        isShutDown = true
        active?.task.cancel()
        active = nil
        stopSignal?.finish()
        stopSignal = nil
        snapshot = .idle
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }

    private func removeSubscriber(_ token: UUID) {
        subscribers.removeValue(forKey: token)
    }

    /// The number of live snapshot observers.
    ///
    /// Internal so tests can prove an observer that goes away is removed: one that is never
    /// removed keeps the coordinator alive for the life of the application.
    var subscriberCount: Int { subscribers.count }

    // MARK: - Actions

    private func toggle() {
        switch snapshot.phase {
        case .idle, .completed, .cancelled, .failed:
            startSession()

        case .preparing, .recording:
            // A second activation ends recording. If the driver has not parked yet the signal
            // is buffered, and its wait returns immediately — that is what makes a toggle
            // pressed during `preparing` land on `.recording` instead of being lost.
            stopSignal?.yield(.stop)

        case .transcribing, .normalizing, .refining, .inserting:
            // Recording has already stopped. A further activation has nothing to stop, and
            // starting a second session here would abandon text the user has already spoken.
            break
        }
    }

    private func startSession() {
        generation &+= 1
        let id = sessionIDs.next()
        let startedAt = dependencies.time.now()
        let (stream, continuation) = AsyncStream.makeStream(of: StopSignal.self)
        stopSignal = continuation

        publish(SessionSnapshot(phase: .preparing, sessionID: id))

        let run = SessionRun(
            id: id,
            generation: generation,
            startedAt: startedAt,
            phaseEnteredAt: startedAt
        )
        let task = Task { await self.drive(run, stopSignal: stream) }
        active = ActiveSession(id: id, generation: generation, task: task)
    }

    private func cancelActiveSession() {
        guard let session = active else { return }
        // Both mechanisms are required and neither subsumes the other: finishing the signal
        // resumes a driver parked on it, while cancelling the task aborts an adapter call
        // already in flight. A cancelled task does not resume a parked continuation.
        stopSignal?.finish()
        session.task.cancel()
    }

    private func dismiss() {
        guard snapshot.phase.isTerminal else { return }
        publish(.idle)
    }

    // MARK: - Session driver

    private func drive(_ initialRun: SessionRun, stopSignal stream: AsyncStream<StopSignal>) async {
        var run = initialRun
        do {
            try await performSession(&run, stopSignal: stream)
            run.outcome = .completed
        } catch let failure as DictationFailure where failure.category == .cancelled {
            run.outcome = .cancelled
        } catch let failure as DictationFailure {
            run.failure = failure
            run.outcome = .failed
        } catch is CancellationError {
            run.outcome = .cancelled
        } catch {
            // An adapter failure that was not mapped. Typed by stage and recoverability, with
            // no provider detail crossing into the domain.
            run.failure = DictationFailure(
                stage: snapshot.phase,
                category: .unknown,
                recoverability: .nonRecoverable
            )
            run.outcome = .failed
        }
        await finalize(run)
    }

    private func performSession(
        _ run: inout SessionRun,
        stopSignal stream: AsyncStream<StopSignal>
    ) async throws {
        // Freeze the context before anything else can change focus.
        let target = await dependencies.targetProvider.captureActiveTarget()
        let settings = await dependencies.settings.currentSettings()
        let mode = dependencies.modeResolver.resolveMode(
            for: target.insertionTarget,
            default: settings.defaultMode
        )
        run.context = SessionContext(
            id: run.id,
            startedAt: run.startedAt.date,
            target: target,
            languageHint: settings.languageHint,
            mode: mode,
            isRefinementEnabled: settings.refinementEnabled
        )

        try await dependencies.capture.prepare()
        try await dependencies.capture.start()
        try advance(to: .recording, run: &run)

        var iterator = stream.makeAsyncIterator()
        guard await iterator.next() != nil else {
            // The signal finished without a stop: the session was cancelled or shut down.
            throw DictationFailure.cancelled(stage: .recording)
        }

        let clip = try await dependencies.capture.stop()
        run.clip = clip
        try advance(to: .transcribing, run: &run)

        let segment = try await trimSpeech(in: clip, run: &run)
        let recognition = try await dependencies.recognition.recognize(
            RecognitionRequest(
                sessionID: run.id,
                audio: clip,
                speechSegment: segment,
                language: run.context?.languageHint ?? .automatic
            )
        )
        run.recognitionEngine = recognition.engine
        run.transcript = Transcript(rawText: recognition.rawText)
        try advance(to: .normalizing, run: &run)

        let normalized = try await normalize(recognition.rawText, run: &run)
        let finalText: String
        if run.context?.isRefinementEnabled == true {
            try advance(to: .refining, run: &run)
            finalText = try await refine(normalized, run: &run)
        } else {
            run.refinement = RefinementSummary(outcome: .skippedByPolicy)
            finalText = normalized
        }
        run.transcript = Transcript(
            rawText: recognition.rawText,
            normalizedText: normalized,
            finalText: finalText
        )

        try advance(to: .inserting, run: &run)
        run.insertion = await dependencies.inserter.insert(
            InsertionRequest(
                sessionID: run.id,
                text: finalText,
                target: run.context?.insertionTarget
            )
        )

        // Insertion is the one port that never throws, so it cannot report that it was
        // cancelled. Without this check a cancellation arriving mid-insertion would be
        // swallowed and the session would report success. The outcome is kept either way, so
        // a cancelled session still tells the user what happened to their text.
        try Task.checkCancellation()
    }

    /// Trims silence, or reports why it could not.
    ///
    /// A detector that fails is non-fatal: the whole clip is transcribed and the degradation
    /// is recorded. A detector that finds no speech is fatal to the session but recoverable by
    /// the user, who can simply dictate again.
    private func trimSpeech(
        in clip: any AudioClip,
        run: inout SessionRun
    ) async throws -> AudioSegment? {
        do {
            switch try await dependencies.voiceActivity.trim(clip) {
            case .speech(let segment):
                return segment.isEmpty ? nil : segment
            case .noSpeech:
                throw DictationFailure(
                    stage: .transcribing,
                    category: .noSpeechDetected,
                    recoverability: .recoverable
                )
            }
        } catch let failure as DictationFailure {
            throw failure
        } catch is CancellationError {
            throw DictationFailure.cancelled(stage: .transcribing)
        } catch {
            run.fallbacks.append(.voiceActivityUnavailable)
            return nil
        }
    }

    /// Runs the deterministic pipeline, falling back to the raw text if it fails.
    private func normalize(_ rawText: String, run: inout SessionRun) async throws -> String {
        guard let context = run.context else { return rawText }
        do {
            let normalized = try await dependencies.textProcessing.process(
                TextProcessingRequest(
                    sessionID: context.id,
                    rawText: rawText,
                    mode: context.mode
                )
            )
            return normalized.text
        } catch is CancellationError {
            throw DictationFailure.cancelled(stage: .normalizing)
        } catch {
            // Never lose valid text: the raw text stands in as the deterministic result.
            run.fallbacks.append(.deterministicProcessingUnavailable)
            return rawText
        }
    }

    /// Refines the deterministic text, falling back to it when the model is unusable.
    ///
    /// Returns the text that should become final. Every rejection path returns the
    /// deterministic text unchanged and records why.
    private func refine(_ normalizedText: String, run: inout SessionRun) async throws -> String {
        guard let context = run.context else { return normalizedText }
        let request = RefinementRequest(
            sessionID: context.id,
            text: normalizedText,
            mode: context.mode
        )

        do {
            let output = try await dependencies.refiner.refine(request)
            switch guardRail.evaluate(output, for: request) {
            case .accepted(let text):
                run.refinement = RefinementSummary(outcome: .refined(output.engine))
                run.refinementEngine = output.engine
                return text
            case .rejected(let reason):
                run.refinement = RefinementSummary(outcome: .rejected(reason))
                run.fallbacks.append(reason)
                return normalizedText
            }
        } catch is CancellationError {
            throw DictationFailure.cancelled(stage: .refining)
        } catch let failure as DictationFailure where failure.category == .cancelled {
            throw failure
        } catch let failure as DictationFailure {
            let reason: FallbackReason =
                failure.category == .timeout ? .refinementTimedOut : .refinementUnavailable
            run.refinement = RefinementSummary(outcome: .unavailable(reason))
            run.fallbacks.append(reason)
            return normalizedText
        } catch {
            run.refinement = RefinementSummary(outcome: .unavailable(.refinementUnavailable))
            run.fallbacks.append(.refinementUnavailable)
            return normalizedText
        }
    }

    // MARK: - Phase ownership

    /// The single choke point for advancing a session.
    ///
    /// Rejects a run whose session has been superseded, and one whose task was cancelled even
    /// though its adapter ignored the cancellation and returned normally.
    @discardableResult
    private func advance(to phase: DictationPhase, run: inout SessionRun) throws -> SessionSnapshot {
        let current = snapshot.phase

        guard !Task.isCancelled else {
            throw DictationFailure.cancelled(stage: current)
        }
        guard active?.generation == run.generation else {
            throw DictationFailure.cancelled(stage: current)
        }
        guard current.canTransition(to: phase) else {
            throw DictationFailure(
                stage: current,
                category: .invalidTransition,
                recoverability: .nonRecoverable
            )
        }

        closeTiming(for: current, run: &run)
        let next = makeSnapshot(phase: phase, run: run)
        publish(next)
        return next
    }

    private func closeTiming(for phase: DictationPhase, run: inout SessionRun) {
        let now = dependencies.time.now()
        run.timings.append(
            StageTiming(phase: phase, duration: now.elapsed(since: run.phaseEnteredAt))
        )
        run.phaseEnteredAt = now
    }

    private func makeSnapshot(phase: DictationPhase, run: SessionRun) -> SessionSnapshot {
        SessionSnapshot(
            phase: phase,
            sessionID: run.id,
            context: run.context,
            // Metadata only. The clip stays private to the actor.
            audio: run.clip?.metadata,
            transcript: run.transcript,
            refinement: run.refinement,
            insertion: run.insertion,
            failure: run.failure,
            fallbacks: run.fallbacks
        )
    }

    private func publish(_ next: SessionSnapshot) {
        snapshot = next
        for continuation in subscribers.values {
            continuation.yield(next)
        }
    }

    // MARK: - Completion

    /// Releases the run's resources and publishes its terminal state.
    ///
    /// Always runs, including for a superseded run, so a late adapter cannot leak a clip. A
    /// superseded run must not publish: a newer session owns the snapshot now.
    private func finalize(_ run: SessionRun) async {
        // No clip means capture never reached a clean stop, so the device is released here.
        // A clip means capture already stopped, and cancelling it would be a redundant call.
        if run.clip == nil {
            await dependencies.capture.cancel()
        }

        guard active?.generation == run.generation else {
            await run.clip?.discard()
            return
        }

        var run = run
        active = nil
        stopSignal = nil

        let terminal = run.terminalPhase
        if snapshot.phase.canTransition(to: terminal) {
            let previous = snapshot.phase
            closeTiming(for: previous, run: &run)
            if terminal == .failed, run.failure == nil {
                run.failure = DictationFailure(
                    stage: previous,
                    category: .unknown,
                    recoverability: .nonRecoverable
                )
            }
            publish(makeSnapshot(phase: terminal, run: run))
        }

        dependencies.metrics.record(makeMetrics(run))
        await run.clip?.discard()

        // Recorded only after the session is no longer active, so a new session starting while
        // history is being written cannot be disturbed by this one finishing.
        //
        // Keyed on reaching insertion rather than on the outcome: text that was handed to the
        // inserter may be in the user's document even when the session was cancelled while
        // that was happening, and a lost history entry would be the only record of it.
        if run.insertion != nil, let context = run.context {
            try? await dependencies.history.record(makeRecord(run, context: context))
        }
    }

    private func makeMetrics(_ run: SessionRun) -> SessionMetrics {
        SessionMetrics(
            sessionID: run.id,
            outcome: run.outcome,
            timings: run.timings,
            fallbacks: run.fallbacks,
            audioDuration: run.clip?.metadata.duration,
            rawCharacterCount: run.transcript.rawText?.count,
            finalCharacterCount: run.transcript.finalText?.count,
            failureCategory: run.failure?.category,
            failureStage: run.failure?.stage
        )
    }

    private func makeRecord(_ run: SessionRun, context: SessionContext) -> SessionRecord {
        SessionRecord(
            sessionID: context.id,
            startedAt: context.startedAt,
            sourceBundleIdentifier: context.application?.bundleIdentifier,
            languageHint: context.languageHint,
            mode: context.mode,
            transcript: run.transcript,
            recognitionEngine: run.recognitionEngine,
            refinementEngine: run.refinementEngine,
            timings: run.timings,
            fallbackReasons: run.fallbacks,
            insertion: run.insertion
        )
    }
}
