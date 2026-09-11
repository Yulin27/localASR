import Testing

@testable import DictationCore

@Suite("Coordinator fallback matrix")
struct CoordinatorFallbackTests {
    private static let normalizingStage = DictationPhase.normalizing
    private static let transcribingStage = DictationPhase.transcribing

    // MARK: - Voice activity

    @Test("No speech fails the session recoverably and transcribes nothing")
    func noSpeechFailsRecoverably() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.voiceActivity.setResponse(.value(.noSpeech))

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.category == .noSpeechDetected)
        #expect(terminal.failure?.stage == .transcribing)
        #expect(terminal.failure?.recoverability == .recoverable)
        #expect(await harness.recognizer.callCount == 0)
        #expect(terminal.transcript == .empty)
        #expect(harness.metrics.last?.outcome == .failed)
        #expect(await harness.history.records.isEmpty)
    }

    @Test("A detector that fails is non-fatal and the untrimmed clip is transcribed")
    func detectorFailureIsNonFatal() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.voiceActivity.setResponse(.unmappedFailure)

        let terminal = try await harness.runSession()
        let requests = await harness.recognizer.requests

        #expect(terminal.phase == .completed)
        #expect(terminal.fallbacks == [.voiceActivityUnavailable])
        #expect(requests.first?.speechSegment == nil)
        #expect(terminal.transcript.finalText == "refined text")
    }

    @Test("A detector that fails keeps its speech segment out of the recognition request")
    func detectorFailureStillReportsNoSegment() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.voiceActivity.setResponse(.value(.speech(AudioSegment(startFrame: 0, endFrame: 0))))

        let terminal = try await harness.runSession()
        let requests = await harness.recognizer.requests

        // An empty segment means nothing was selected, which is the same as no selection.
        #expect(terminal.phase == .completed)
        #expect(requests.first?.speechSegment == nil)
    }

    // MARK: - Recognition

    @Test("A recognition failure fails the session with its category and stage")
    func recognitionFailureIsTyped() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.recognizer.setResponse(
            .failure(
                DictationFailure(
                    stage: .transcribing,
                    category: .modelUnavailable,
                    recoverability: .recoverable
                )
            )
        )

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.category == .modelUnavailable)
        #expect(terminal.failure?.stage == .transcribing)
        #expect(terminal.transcript == .empty)
        #expect(harness.metrics.last?.failureCategory == .modelUnavailable)
        #expect(harness.metrics.last?.failureStage == .transcribing)
    }

    @Test("An unmapped adapter error becomes a typed failure with no provider detail")
    func unmappedAdapterErrorIsTyped() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.recognizer.setResponse(.unmappedFailure)

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .failed)
        #expect(terminal.failure?.category == .unknown)
        #expect(terminal.failure?.stage == .transcribing)
        #expect(terminal.failure?.diagnosticCode == nil)
    }

    // MARK: - Deterministic processing

    @Test("A deterministic failure falls back to the raw text and keeps going")
    func deterministicFailureFallsBackToRawText() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.processor.setResponse(
            .failure(
                DictationFailure(
                    stage: Self.normalizingStage,
                    category: .runtimeFailure,
                    recoverability: .recoverable
                )
            )
        )

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.transcript.rawText == "raw text")
        #expect(terminal.transcript.normalizedText == "raw text")
        #expect(terminal.fallbacks == [.deterministicProcessingUnavailable])
        // The refiner still ran, on the raw text.
        let requests = await harness.refiner.requests
        #expect(requests.first?.text == "raw text")
    }

    // MARK: - Refinement

    @Test("A refiner failure preserves the deterministic text")
    func refinerFailurePreservesDeterministicText() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.refiner.setResponse(
            .failure(
                DictationFailure(
                    stage: .refining,
                    category: .runtimeFailure,
                    recoverability: .recoverable
                )
            )
        )

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.transcript.normalizedText == "normalized text")
        #expect(terminal.transcript.finalText == "normalized text")
        #expect(terminal.refinement?.outcome == .unavailable(.refinementUnavailable))
        #expect(terminal.fallbacks == [.refinementUnavailable])
    }

    @Test("A refiner deadline is reported as a timeout rather than a generic failure")
    func refinerTimeoutIsReportedAsSuch() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.refiner.setResponse(
            .failure(
                DictationFailure(
                    stage: .refining,
                    category: .timeout,
                    recoverability: .recoverable
                )
            )
        )

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.refinement?.outcome == .unavailable(.refinementTimedOut))
        #expect(terminal.fallbacks == [.refinementTimedOut])
        #expect(terminal.transcript.finalText == "normalized text")
    }

    @Test("An unmapped refiner error still preserves the deterministic text")
    func unmappedRefinerErrorFallsBack() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.refiner.setResponse(.unmappedFailure)

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.transcript.finalText == "normalized text")
        #expect(terminal.fallbacks == [.refinementUnavailable])
    }

    @Test("Rejected refinement output is discarded in favour of deterministic text")
    func rejectedRefinementKeepsDeterministicText() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        // Far longer than the mode allows.
        await harness.refiner.setResponse(
            .value(
                RefinementOutput(
                    text: String(repeating: "normalized text ", count: 20),
                    engine: EngineIdentifier(name: "fake-refiner")
                )
            )
        )

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.transcript.finalText == "normalized text")
        #expect(terminal.refinement?.outcome == .rejected(.refinementLengthOutOfRange))
        #expect(terminal.fallbacks == [.refinementLengthOutOfRange])
    }

    @Test("Empty refinement output is rejected")
    func emptyRefinementOutputIsRejected() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.refiner.setResponse(
            .value(RefinementOutput(text: "   ", engine: EngineIdentifier(name: "fake-refiner")))
        )

        let terminal = try await harness.runSession()

        #expect(terminal.transcript.finalText == "normalized text")
        #expect(terminal.refinement?.outcome == .rejected(.refinementEmptyOutput))
    }

    @Test("Contaminated refinement output is rejected")
    func contaminatedRefinementOutputIsRejected() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.refiner.setResponse(
            .value(
                RefinementOutput(
                    text: "<thinking>clean it up</thinking>normalized text",
                    engine: EngineIdentifier(name: "fake-refiner")
                )
            )
        )

        let terminal = try await harness.runSession()

        #expect(terminal.transcript.finalText == "normalized text")
        #expect(terminal.refinement?.outcome == .rejected(.refinementContaminated))
    }

    @Test("Accepted refinement becomes the final text and is recorded with its engine")
    func acceptedRefinementBecomesFinalText() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        let terminal = try await harness.runSession()

        #expect(terminal.transcript.finalText == "refined text")
        #expect(terminal.transcript.normalizedText == "normalized text")
        #expect(terminal.transcript.rawText == "raw text")
        #expect(terminal.refinement?.outcome == .refined(EngineIdentifier(name: "fake-refiner", version: "1")))
        #expect(terminal.fallbacks.isEmpty)
    }

    // MARK: - Insertion

    @Test("A failed insertion still completes the session and keeps the text copyable")
    func failedInsertionKeepsTheText() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.inserter.setOutcome(.failed(.targetUnavailable))

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.insertion?.delivery == .failed)
        #expect(terminal.insertion?.failure == .targetUnavailable)
        #expect(terminal.transcript.finalText == "refined text")
    }

    @Test("A copy-only insertion is reported as such and keeps the text")
    func copyOnlyInsertionIsReported() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.inserter.setOutcome(.copiedOnly(.secureInputBlocked))

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.insertion?.delivery == .copiedOnly)
        #expect(terminal.insertion?.failure == .secureInputBlocked)
        #expect(terminal.transcript.finalText == "refined text")
    }

    @Test("A pasted result is not reported as confirmed")
    func pastedResultIsNotConfirmed() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.inserter.setOutcome(
            InsertionOutcome(delivery: .pasteRequested, verification: .unconfirmed)
        )

        let terminal = try await harness.runSession()

        #expect(terminal.insertion?.delivery == .pasteRequested)
        #expect(terminal.insertion?.verification == .unconfirmed)
    }

    // MARK: - History and metrics

    @Test("A history write failure never downgrades a completed dictation")
    func historyFailureDoesNotDowngradeTheSession() async throws {
        let harness = DictationHarness()
        await harness.allowAll()
        await harness.history.setWriteError(UnmappedProviderError())

        let terminal = try await harness.runSession()

        #expect(terminal.phase == .completed)
        #expect(terminal.transcript.finalText == "refined text")
        #expect(harness.metrics.all.count == 1)
        #expect(harness.metrics.last?.outcome == .completed)
    }

    @Test("Every session records metrics exactly once, cancelled ones included")
    func metricsAreRecordedOncePerSession() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        _ = try await harness.runSession()
        try await harness.startRecording()
        await harness.coordinator.handle(.cancel)
        _ = try await harness.waitForTerminal()

        #expect(harness.metrics.all.map(\.outcome) == [.completed, .cancelled])
    }

    @Test("A recovery succeeds after a failure, with no state carried over")
    func sessionAfterAFailureStartsClean() async throws {
        let harness = DictationHarness()
        await harness.allowAll()

        await harness.recognizer.setResponse(
            .failure(
                DictationFailure(
                    stage: .transcribing,
                    category: .modelUnavailable,
                    recoverability: .recoverable
                )
            )
        )
        let failed = try await harness.runSession()
        #expect(failed.phase == .failed)

        await harness.recognizer.setResponse(
            .value(
                RecognitionResult(
                    rawText: "raw text",
                    engine: EngineIdentifier(name: "fake-asr", version: "1")
                )
            )
        )
        let recovered = try await harness.runSession()

        #expect(recovered.phase == .completed)
        #expect(recovered.failure == nil)
        #expect(recovered.fallbacks.isEmpty)
        #expect(recovered.transcript.finalText == "refined text")
        #expect(harness.metrics.all.map(\.outcome) == [.failed, .completed])
    }
}
