import Testing

@testable import DictationCore

/// These assertions are compile-time. If a value type gains a non-`Sendable` member, or a
/// port stops refining `Sendable`, this file stops compiling — which is the point: a value
/// that crosses an actor boundary unsafely should be caught here rather than in Phase 3.
@Suite("Sendable conformance")
struct SendableTests {
    @Test("Core value types are Sendable")
    func valueTypesAreSendable() {
        requireSendable(SessionID.self)
        requireSendable(SessionIDGenerator.self)
        requireSendable(LanguageHint.self)
        requireSendable(RefinementMode.self)
        requireSendable(DictationSettings.self)
        requireSendable(AudioFormat.self)
        requireSendable(CaptureOrigin.self)
        requireSendable(AudioClipMetadata.self)
        requireSendable(AudioSamples.self)
        requireSendable(AudioSegment.self)
        requireSendable(Transcript.self)
        requireSendable(NormalizedText.self)
        requireSendable(TransformIdentifier.self)
        requireSendable(EngineIdentifier.self)
        requireSendable(ActiveApplication.self)
        requireSendable(InsertionTarget.self)
        requireSendable(TargetUnavailableReason.self)
        requireSendable(TargetCaptureResult.self)
        requireSendable(SessionContext.self)
        requireSendable(DictationPhase.self)
        requireSendable(DictationAction.self)
        requireSendable(FailureCategory.self)
        requireSendable(Recoverability.self)
        requireSendable(DictationFailure.self)
        requireSendable(FallbackReason.self)
        requireSendable(RefinementSummary.self)
        requireSendable(InsertionDelivery.self)
        requireSendable(InsertionVerification.self)
        requireSendable(InsertionFailure.self)
        requireSendable(InsertionOutcome.self)
        requireSendable(SessionSnapshot.self)
        requireSendable(StageTiming.self)
        requireSendable(SessionMetrics.self)
        requireSendable(ZeroEditFeedback.self)
        requireSendable(SessionRecord.self)
    }

    @Test("Port payload types are Sendable")
    func portPayloadsAreSendable() {
        requireSendable(VoiceActivityOutcome.self)
        requireSendable(RecognitionRequest.self)
        requireSendable(RecognitionResult.self)
        requireSendable(TextProcessingRequest.self)
        requireSendable(RefinementRequest.self)
        requireSendable(RefinementOutput.self)
        requireSendable(InsertionRequest.self)
        requireSendable(Timestamp.self)
    }

    @Test("An audio clip existential is Sendable")
    func audioClipExistentialIsSendable() {
        requireSendable((any AudioClip).self)
    }

    @Test("Every port existential is Sendable, so it can be stored in the coordinator")
    func portExistentialsAreSendable() {
        requireSendable((any AudioCapturing).self)
        requireSendable((any VoiceActivityDetecting).self)
        requireSendable((any SpeechRecognizing).self)
        requireSendable((any DeterministicTextProcessing).self)
        requireSendable((any TextRefining).self)
        requireSendable((any TextInserting).self)
        requireSendable((any ActiveApplicationProviding).self)
        requireSendable((any ModeResolving).self)
        requireSendable((any HistoryStoring).self)
        requireSendable((any MetricsRecording).self)
        requireSendable((any DictationSettingsProviding).self)
        requireSendable((any TimeSource).self)
    }
}
