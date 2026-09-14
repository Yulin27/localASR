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
        /// How far this run has got, which is not always what observers are being shown.
        ///
        /// The published snapshot is a projection for the UI, and the two separate exactly
        /// where it matters: before the destination is frozen nothing has been published yet,
        /// and after the user cancels, `.cancelled` is published while this run is still
        /// unwinding out of an adapter call. Validating transitions and closing stage timings
        /// against the run keeps both of those honest.
        var phase: DictationPhase = .preparing
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
        // A hotkey event can still arrive while the application is terminating, or after the
        // composition root has been rebuilt. Starting a session then would open the microphone
        // with no observer left to show that it is open.
        guard !isShutDown else { return }

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

        // The state machine enters `preparing` now, so a second activation stops this session
        // rather than starting another one. Observers are not told yet: the destination is
        // captured in the task below, and a view that reacted to `preparing` by opening a
        // panel would move the focus this session is about to freeze. `performSession`
        // publishes the first snapshot once the context is frozen.
        setState(SessionSnapshot(phase: .preparing, sessionID: id))

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

        // The coordinator gives the session up here rather than when its driver finally
        // returns. Cancelling a task does not stop an adapter that never checks for it, and a
        // recognition call on a long recording can take tens of seconds to come back — until
        // then the user would be watching `transcribing`, with `toggleRecording` landing in
        // the processing branch and no way to start dictating again.
        //
        // The abandoned run keeps only its cleanup. It no longer owns the published state, so
        // `finalize` releases the device, discards the clip, writes any history the session
        // earned and records its metrics, without publishing anything.
        active = nil
        stopSignal = nil
        if snapshot.phase.canTransition(to: .cancelled) {
            // Moved rather than rebuilt: a session cancelled during refinement has already
            // produced deterministic text, and the terminal snapshot is where the user still
            // sees it.
            publish(snapshot.moved(to: .cancelled))
        }
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
        } catch {
            // Cancellation is decided by the task, not by the error's type. An adapter
            // interrupted by a cancel commonly throws an error of its own — the user still
            // cancelled, and reporting that as a failure would show them an error for
            // something they asked for.
            if Task.isCancelled || active?.generation != run.generation {
                run.outcome = .cancelled
            } else if let failure = error as? DictationFailure {
                run.outcome = failure.category == .cancelled ? .cancelled : .failed
                run.failure = failure.category == .cancelled ? nil : failure
            } else {
                // An adapter failure that was not mapped. Typed by stage and recoverability,
                // with no provider detail crossing into the domain.
                run.failure = DictationFailure(
                    stage: run.phase,
                    category: .unknown,
                    recoverability: .nonRecoverable
                )
                run.outcome = .failed
            }
        }
        await finalize(run)
    }

    private func performSession(
        _ run: inout SessionRun,
        stopSignal stream: AsyncStream<StopSignal>
    ) async throws {
        // Freeze the context before anything else can change focus.
        let target = await dependencies.targetProvider.captureActiveTarget()
        try ensureStillOwns(run, stage: .preparing)

        let settings = await dependencies.settings.currentSettings()
        try ensureStillOwns(run, stage: .preparing)

        // Resolved from the frontmost application, not from the destination: reading which
        // application is frontmost needs no Accessibility permission, so a session that could
        // not resolve a focused element still knows which app's written form it wants.
        let mode = dependencies.modeResolver.resolveMode(
            for: target.application,
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

        // The first snapshot observers see for this session, and it already carries the
        // destination. `ARCHITECTURE.md` requires the destination to be captured before any
        // overlay or asynchronous work can change focus, which a snapshot published earlier
        // would break: a HUD shown on `preparing` takes focus, and the session would freeze
        // LocalASR, or the wrong field, as the place its text belongs.
        publish(makeSnapshot(phase: .preparing, run: run))

        try await dependencies.capture.prepare()
        // A microphone that turns on after the user cancelled is a privacy failure, so the
        // cancellation is honoured here rather than at the next phase change.
        try ensureStillOwns(run, stage: .preparing)

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
        try ensureStillOwns(run, stage: .transcribing)

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
        try ensureNotEmpty(recognition.rawText, stage: .transcribing)
        try advance(to: .normalizing, run: &run)

        let normalized = try await normalize(recognition.rawText, run: &run)
        // Filler-only speech normalises to nothing. Inserting it would be a no-op at best, and
        // with a paste-based inserter it would clear the clipboard the user was keeping.
        try ensureNotEmpty(normalized, stage: .normalizing)

        // Published before refinement, which can take seconds: `Transcript` promises that an
        // earlier stage is never discarded, so anything shown or copied meanwhile — including
        // the terminal snapshot of a session cancelled here — is the deterministic text rather
        // than raw recognition output.
        run.transcript = Transcript(rawText: recognition.rawText, normalizedText: normalized)

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
        try ensureStillOwns(run, stage: .inserting)
    }

    /// Fails a session whose text has run out.
    ///
    /// Recognition that heard nothing, and deterministic processing that removed the last
    /// filler, both leave nothing to deliver. Refining it is worse than useless: a model given
    /// an empty transcript writes a plausible sentence of its own, and that is not the user's
    /// words.
    private func ensureNotEmpty(_ text: String, stage: DictationPhase) throws {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        throw DictationFailure(
            stage: stage,
            category: .emptyTranscript,
            recoverability: .recoverable
        )
    }

    /// Throws unless `run` is still the session the coordinator owns and its task is live.
    ///
    /// ADR 0003 requires a cancellation to be honoured at every await boundary. An adapter may
    /// return perfectly good results after the user cancelled — many never check for it — so
    /// each boundary is checked here rather than trusted to the adapter.
    private func ensureStillOwns(_ run: SessionRun, stage: DictationPhase) throws {
        guard !Task.isCancelled, active?.generation == run.generation else {
            throw DictationFailure.cancelled(stage: stage)
        }
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
        // Only the `trim` call is guarded: a `.noSpeech` outcome is this coordinator's decision
        // to fail the session, and it must not be caught by the detector's own fallback below.
        let outcome: VoiceActivityOutcome
        do {
            outcome = try await dependencies.voiceActivity.trim(clip)
        } catch {
            try cancelledIfSessionWas(stage: .transcribing)
            // `VoiceActivityDetecting.trim` documents throwing as non-fatal whatever the
            // adapter throws, including a `DictationFailure` it mapped itself. A detector that
            // cannot load its model must not cost the user a recording that is already made.
            run.fallbacks.append(.voiceActivityUnavailable)
            return nil
        }

        switch outcome {
        case .speech(let segment):
            return segment.isEmpty ? nil : segment
        case .noSpeech:
            throw DictationFailure(
                stage: .transcribing,
                category: .noSpeechDetected,
                recoverability: .recoverable
            )
        }
    }

    /// Rethrows an adapter error as this session's cancellation, but only if the session really
    /// was cancelled.
    ///
    /// The error's type does not decide this. An adapter interrupted by a cancellation usually
    /// reports it as a failure of its own, and an adapter can raise `CancellationError` while
    /// the session is perfectly live — a refiner enforcing its own deadline on a child task
    /// does exactly that. Deciding from `Task.isCancelled` keeps both directions right.
    private func cancelledIfSessionWas(stage: DictationPhase) throws {
        guard Task.isCancelled else { return }
        throw DictationFailure.cancelled(stage: stage)
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
        } catch {
            try cancelledIfSessionWas(stage: .normalizing)
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
        } catch {
            try cancelledIfSessionWas(stage: .refining)
            let timedOut = (error as? DictationFailure)?.category == .timeout
            let reason: FallbackReason = timedOut ? .refinementTimedOut : .refinementUnavailable
            run.refinement = RefinementSummary(outcome: .unavailable(reason))
            run.fallbacks.append(reason)
            return normalizedText
        }
    }

    // MARK: - Phase ownership

    /// The single choke point for advancing a session.
    ///
    /// Rejects a run whose session has been superseded, and one whose task was cancelled even
    /// though its adapter ignored the cancellation and returned normally.
    ///
    /// Validated against the run's own phase rather than the published one. They agree for
    /// most of a session, and where they do not — a cancelled session is published as
    /// `.cancelled` while this run is still unwinding — the run's phase is the one that
    /// describes what it may do next.
    @discardableResult
    private func advance(to phase: DictationPhase, run: inout SessionRun) throws -> SessionSnapshot {
        let current = run.phase

        try ensureStillOwns(run, stage: current)
        guard current.canTransition(to: phase) else {
            throw DictationFailure(
                stage: current,
                category: .invalidTransition,
                recoverability: .nonRecoverable
            )
        }

        closeTiming(for: current, run: &run)
        run.phase = phase
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

    /// Records the coordinator's state without telling observers.
    ///
    /// For the one state change they must not act on yet: a session enters `preparing` the
    /// moment the shortcut is pressed, but its destination is only frozen a moment later.
    private func setState(_ next: SessionSnapshot) {
        snapshot = next
    }

    private func publish(_ next: SessionSnapshot) {
        setState(next)
        for continuation in subscribers.values {
            continuation.yield(next)
        }
    }

    // MARK: - Completion

    /// Releases the run's resources, accounts for it, and publishes its terminal state.
    ///
    /// Always runs, including for a run the coordinator has already given up on, so a late
    /// adapter can leak neither the clip nor the session's only record of itself. Three
    /// questions are asked separately, because a session the user cancelled while an adapter
    /// was still working answers them differently:
    ///
    /// - May this run publish? Only while it still owns the coordinator's state. A cancelled
    ///   session was published as `.cancelled` the moment the user asked, and a superseded one
    ///   does not own the snapshot at all.
    /// - Must it release the device? Unless a newer session has already taken it over.
    /// - Must it clean up and account for itself? Always.
    private func finalize(_ run: SessionRun) async {
        var run = run
        let ownsPublishedState = active?.generation == run.generation
        // Strictly newer, so a session the user cancelled — which leaves no successor — still
        // releases the microphone it opened.
        let deviceTakenByNewerSession = active.map { $0.generation > run.generation } ?? false

        if ownsPublishedState {
            active = nil
            stopSignal = nil
        }

        let terminal = run.terminalPhase
        let reachedTerminal = run.phase.canTransition(to: terminal)
        if reachedTerminal {
            let previous = run.phase
            closeTiming(for: previous, run: &run)
            if terminal == .failed, run.failure == nil {
                run.failure = DictationFailure(
                    stage: previous,
                    category: .unknown,
                    recoverability: .nonRecoverable
                )
            }
            run.phase = terminal
        }

        // History is keyed on reaching insertion rather than on the outcome: text handed to the
        // inserter may be in the user's document even when the session was cancelled while that
        // was happening, and a lost entry would be the only record of it. It is written before
        // the terminal snapshot, so an observer that reads history on seeing the session end
        // cannot read it too early.
        let record = run.insertion != nil ? run.context.map { makeRecord(run, context: $0) } : nil

        // No clip means capture never reached a clean stop, so the device is released here.
        // A clip means capture already stopped, and cancelling it would be a redundant call.
        let historyWriteFailed = await release(
            clip: run.clip,
            releasingDevice: run.clip == nil && !deviceTakenByNewerSession,
            record: record
        )
        if historyWriteFailed {
            run.fallbacks.append(.historyUnavailable)
        }

        if ownsPublishedState, reachedTerminal {
            publish(makeSnapshot(phase: terminal, run: run))
        }
        dependencies.metrics.record(makeMetrics(run))
    }

    /// Releases a finished session's resources and writes its history entry, reporting whether
    /// that write was lost.
    ///
    /// Runs in an unstructured task, which does not inherit cancellation, because `finalize`
    /// runs inside the session's own task: for a cancelled session every call here would
    /// otherwise start out cancelled, and a store or a disk-backed clip that honours
    /// cancellation — as most file and database APIs do — would silently skip its work.
    /// Awaiting the task keeps the ordering deterministic: nothing observes the terminal
    /// snapshot before the device is released and the record is written.
    private func release(
        clip: (any AudioClip)?,
        releasingDevice: Bool,
        record: SessionRecord?
    ) async -> Bool {
        let dependencies = self.dependencies
        return await Task {
            if releasingDevice {
                await dependencies.capture.cancel()
            }
            await clip?.discard()
            guard let record else { return false }
            do {
                try await dependencies.history.record(record)
                return false
            } catch {
                // A failed write never downgrades a dictation that already delivered: the text
                // is in the target or on the clipboard either way. It is reported as a
                // degradation rather than swallowed, so a store that is failing every write is
                // visible instead of quietly losing the user's history.
                return true
            }
        }.value
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
