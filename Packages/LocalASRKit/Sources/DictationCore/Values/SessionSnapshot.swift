import Foundation

/// How a refinement attempt ended.
public struct RefinementSummary: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// Accepted by the output guard, which runs outside the model adapter.
        case refined(EngineIdentifier)
        /// The session's policy was `.deterministicOnly`.
        case skippedByPolicy
        /// The refiner produced output the guard rejected. Deterministic text is kept.
        case rejected(FallbackReason)
        /// The refiner failed, timed out, or returned nothing usable. Deterministic text
        /// is kept.
        case unavailable(FallbackReason)
    }

    public let outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }
}

/// How the text was delivered.
public enum InsertionDelivery: String, Sendable, Equatable, Codable {
    /// Written through the Accessibility API.
    case insertedDirectly
    /// A clipboard transaction followed by a synthetic paste.
    case pasteRequested
    /// The clipboard only, with the text left for the user to place.
    case copiedOnly
    case failed
}

/// Whether delivery was confirmed.
///
/// A posted paste event is not confirmation that the target accepted the text, so this is
/// tracked separately from ``InsertionDelivery``.
public enum InsertionVerification: String, Sendable, Equatable, Codable {
    case confirmed
    case unconfirmed
    case notAttempted
    case unavailable
}

/// Why insertion did not deliver the text.
public enum InsertionFailure: String, Sendable, Equatable, Codable {
    case cancelled
    /// The session had no destination to insert into.
    case noTarget
    case accessibilityPermissionDenied
    case secureTextField
    case secureInputBlocked
    case targetUnavailable
    case applicationUnresponsive
    case pasteSuppressed
}

/// The structured result of the insertion transaction.
public struct InsertionOutcome: Sendable, Equatable {
    public let delivery: InsertionDelivery
    public let verification: InsertionVerification
    public let failure: InsertionFailure?

    public init(
        delivery: InsertionDelivery,
        verification: InsertionVerification,
        failure: InsertionFailure? = nil
    ) {
        self.delivery = delivery
        self.verification = verification
        self.failure = failure
    }

    /// The text could not be placed but is on the clipboard, so nothing is lost.
    public static func copiedOnly(
        _ failure: InsertionFailure,
        verification: InsertionVerification = .notAttempted
    ) -> InsertionOutcome {
        InsertionOutcome(delivery: .copiedOnly, verification: verification, failure: failure)
    }

    public static func failed(
        _ failure: InsertionFailure,
        verification: InsertionVerification = .notAttempted
    ) -> InsertionOutcome {
        InsertionOutcome(delivery: .failed, verification: verification, failure: failure)
    }
}

/// An immutable view of a session, safe to hand to the UI.
///
/// It carries no framework objects and no audio samples — only ``AudioClipMetadata`` — so
/// rendering a snapshot can never extend a recording's lifetime or leak PCM across an
/// isolation boundary.
public struct SessionSnapshot: Sendable, Equatable {
    /// Present from the first snapshot of a session, which is published before the
    /// destination and preferences have been captured.
    public let sessionID: SessionID?

    public let phase: DictationPhase

    /// The frozen context. `nil` only during `preparing`, before capture completes.
    public let context: SessionContext?

    public let audio: AudioClipMetadata?
    public let transcript: Transcript
    public let refinement: RefinementSummary?
    public let insertion: InsertionOutcome?
    public let failure: DictationFailure?
    /// Non-fatal degradations, in the order they happened.
    public let fallbacks: [FallbackReason]

    public init(
        phase: DictationPhase,
        sessionID: SessionID? = nil,
        context: SessionContext? = nil,
        audio: AudioClipMetadata? = nil,
        transcript: Transcript = .empty,
        refinement: RefinementSummary? = nil,
        insertion: InsertionOutcome? = nil,
        failure: DictationFailure? = nil,
        fallbacks: [FallbackReason] = []
    ) {
        self.sessionID = sessionID
        self.phase = phase
        self.context = context
        self.audio = audio
        self.transcript = transcript
        self.refinement = refinement
        self.insertion = insertion
        self.failure = failure
        self.fallbacks = fallbacks
    }

    public static let idle = SessionSnapshot(phase: .idle)

    /// Returns a copy with one fallback appended, keeping the first occurrence's position.
    public func appending(fallback: FallbackReason) -> SessionSnapshot {
        var fallbacks = self.fallbacks
        if !fallbacks.contains(fallback) {
            fallbacks.append(fallback)
        }
        return SessionSnapshot(
            phase: phase,
            sessionID: sessionID,
            context: context,
            audio: audio,
            transcript: transcript,
            refinement: refinement,
            insertion: insertion,
            failure: failure,
            fallbacks: fallbacks
        )
    }
}
