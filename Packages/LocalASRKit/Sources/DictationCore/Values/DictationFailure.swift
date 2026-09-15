import Foundation

/// What went wrong, independent of which adapter reported it.
///
/// Provider error strings never become domain decisions; adapters map their failures onto
/// these categories.
public enum FailureCategory: String, Sendable, Equatable, Codable {
    /// Control-flow, not a user-visible failure: the coordinator unwinds a cancelled or
    /// superseded session through the same path as a real failure.
    case cancelled
    case permissionDenied
    case deviceUnavailable
    /// Voice activity detection found no speech worth transcribing.
    case noSpeechDetected
    /// Recognition ran and produced nothing usable.
    case emptyTranscript
    /// A model or engine was not prepared when the session needed it.
    case modelUnavailable
    case runtimeFailure
    case timeout
    case invalidTarget
    /// A phase transition outside the truth table. Reaching this is a defect.
    case invalidTransition
    case unsupported
    case unknown
}

/// Whether repeating the same interaction could succeed.
public enum Recoverability: String, Sendable, Equatable, Codable {
    /// The user can act on it: press the shortcut again, grant a permission, choose another
    /// field.
    case recoverable
    /// Repeating the same interaction will not help without a state change.
    case nonRecoverable
}

/// A typed failure, attributed to the phase it occurred in.
public struct DictationFailure: Error, Sendable, Equatable {
    public let stage: DictationPhase
    public let category: FailureCategory
    public let recoverability: Recoverability

    /// A short, privacy-safe identifier for diagnostics.
    ///
    /// Never contains transcript text, audio, prompts, clipboard contents, cursor context,
    /// or file paths.
    public let diagnosticCode: String?

    public init(
        stage: DictationPhase,
        category: FailureCategory,
        recoverability: Recoverability,
        diagnosticCode: String? = nil
    ) {
        self.stage = stage
        self.category = category
        self.recoverability = recoverability
        self.diagnosticCode = diagnosticCode
    }

    /// The control-flow signal used to unwind a cancelled or superseded session.
    public static func cancelled(stage: DictationPhase) -> DictationFailure {
        DictationFailure(stage: stage, category: .cancelled, recoverability: .recoverable)
    }
}

/// A non-fatal deviation from the ideal pipeline.
///
/// A fallback means a later stage gave up and the session continued on an earlier, safer
/// value — never that text was lost. The list is recorded per session because `Spec.md`'s
/// history record requires a fallback reason, and because a rising rate here is the earliest
/// signal that a model or an adapter is degrading.
public enum FallbackReason: String, Sendable, Equatable, Codable, CaseIterable {
    /// Voice activity detection failed, so the untrimmed clip was recognized.
    case voiceActivityUnavailable
    /// Deterministic processing failed, so the raw text was used unchanged.
    case deterministicProcessingUnavailable
    case refinementUnavailable
    case refinementTimedOut
    case refinementEmptyOutput
    /// The output grew or shrank beyond the mode's permitted ratio. Structured mode is
    /// expected to expand, so the limits are per mode.
    case refinementLengthOutOfRange
    /// The output lost or damaged the script or language of the input.
    case refinementLanguageDamage
    /// The output contains reasoning or assistant framing rather than the cleaned transcript.
    case refinementContaminated
    /// The output opens with assistant preamble such as "here is the cleaned version".
    case refinementPreamble
    /// The session's history entry could not be written. The dictation itself still
    /// delivered, so this never fails a session — but a store that is failing every write
    /// loses the user's history, and that must be visible rather than silent.
    case historyUnavailable
}
