import Foundation

/// One pipeline stage's wall-clock cost.
///
/// Privacy-safe by construction: a phase and a duration, and nothing else.
public struct StageTiming: Sendable, Equatable {
    public let phase: DictationPhase
    public let duration: Duration

    public init(phase: DictationPhase, duration: Duration) {
        self.phase = phase
        self.duration = duration
    }
}

/// A privacy-safe per-session summary.
///
/// It exists so latency, fallback behaviour, and failure rates can be observed without any
/// transcript text, audio, prompt, or clipboard content ever reaching a log or a metric.
public struct SessionMetrics: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable, Codable {
        case completed
        case cancelled
        case failed
    }

    public let sessionID: SessionID
    public let outcome: Outcome
    public let timings: [StageTiming]
    public let fallbacks: [FallbackReason]
    public let audioDuration: Duration?
    /// Character counts, never text.
    public let rawCharacterCount: Int?
    public let finalCharacterCount: Int?
    public let failureCategory: FailureCategory?
    public let failureStage: DictationPhase?

    public init(
        sessionID: SessionID,
        outcome: Outcome,
        timings: [StageTiming] = [],
        fallbacks: [FallbackReason] = [],
        audioDuration: Duration? = nil,
        rawCharacterCount: Int? = nil,
        finalCharacterCount: Int? = nil,
        failureCategory: FailureCategory? = nil,
        failureStage: DictationPhase? = nil
    ) {
        self.sessionID = sessionID
        self.outcome = outcome
        self.timings = timings
        self.fallbacks = fallbacks
        self.audioDuration = audioDuration
        self.rawCharacterCount = rawCharacterCount
        self.finalCharacterCount = finalCharacterCount
        self.failureCategory = failureCategory
        self.failureStage = failureStage
    }
}

/// The user's explicit judgement on whether a delivered result needed editing.
///
/// `Spec.md` calls the zero-edit rate the metric that actually matters, and v0.1 records it
/// by hand. It lives on the history record, which is why that record must keep enough to
/// re-read the result without keeping the audio or anything around the cursor.
public struct ZeroEditFeedback: Sendable, Equatable, Codable {
    public enum Judgement: String, Sendable, Equatable, Codable {
        /// Delivered as-is.
        case unchanged
        /// The user changed something.
        case edited
    }

    public let judgement: Judgement
    public let recordedAt: Date

    public init(judgement: Judgement, recordedAt: Date) {
        self.judgement = judgement
        self.recordedAt = recordedAt
    }
}

/// One entry in the bounded recent-history list.
///
/// Storage encoding is a Phase 10 decision, so this value deliberately does not commit to
/// `Codable` yet.
public struct SessionRecord: Sendable, Equatable {
    public let sessionID: SessionID
    public let startedAt: Date
    public let sourceBundleIdentifier: String?
    public let languageHint: LanguageHint
    /// Absent when refinement was disabled for the session.
    public let mode: RefinementMode?
    public let transcript: Transcript
    public let recognitionEngine: EngineIdentifier?
    public let refinementEngine: EngineIdentifier?
    public let timings: [StageTiming]
    public let fallbackReasons: [FallbackReason]
    public let insertion: InsertionOutcome?
    public let zeroEditFeedback: ZeroEditFeedback?

    public init(
        sessionID: SessionID,
        startedAt: Date,
        sourceBundleIdentifier: String? = nil,
        languageHint: LanguageHint,
        mode: RefinementMode? = nil,
        transcript: Transcript = .empty,
        recognitionEngine: EngineIdentifier? = nil,
        refinementEngine: EngineIdentifier? = nil,
        timings: [StageTiming] = [],
        fallbackReasons: [FallbackReason] = [],
        insertion: InsertionOutcome? = nil,
        zeroEditFeedback: ZeroEditFeedback? = nil
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.languageHint = languageHint
        self.mode = mode
        self.transcript = transcript
        self.recognitionEngine = recognitionEngine
        self.refinementEngine = refinementEngine
        self.timings = timings
        self.fallbackReasons = fallbackReasons
        self.insertion = insertion
        self.zeroEditFeedback = zeroEditFeedback
    }
}
