import Foundation

/// A request to transcribe one recording.
public struct RecognitionRequest: Sendable {
    public let sessionID: SessionID
    public let audio: any AudioClip

    /// The frame range voice activity selected, or `nil` to transcribe the whole clip — which
    /// is what happens when the detector was unavailable.
    public let speechSegment: AudioSegment?

    /// The hint frozen into the session context. Recognition is the only stage that receives
    /// one; see ``SpeechRecognizing`` for how an adapter must treat it.
    public let language: LanguageHint

    public init(
        sessionID: SessionID,
        audio: any AudioClip,
        speechSegment: AudioSegment? = nil,
        language: LanguageHint
    ) {
        self.sessionID = sessionID
        self.audio = audio
        self.speechSegment = speechSegment
        self.language = language
    }
}

/// The result of one recognition pass.
public struct RecognitionResult: Sendable, Equatable {
    /// The direct recognition output. Later stages never overwrite it.
    public let rawText: String

    public let engine: EngineIdentifier

    public init(rawText: String, engine: EngineIdentifier) {
        self.rawText = rawText
        self.engine = engine
    }
}

/// Batch speech recognition.
///
/// Deliberately batch: v0.1 delivers one final result rather than streaming text into the
/// target, and streaming belongs in a separate protocol when it enters the accepted scope.
/// An implementation may chunk internally for long input while still returning one result.
///
/// An implementation maps ``RecognitionRequest/language`` onto the language codes its runtime
/// knows, and treats a hint it cannot map as ``LanguageHint/automatic``. It never passes an
/// unvalidated value into a decoder prompt: that turns a settings error into plausible wrong
/// transcripts with nothing in the metrics to show for it. It does not throw over a hint
/// either, because a settings mistake must not cost the user their dictation.
///
/// The result carries no language. No runtime in scope reports the language it recognised,
/// and a value filled in by a text classifier would claim a provenance it does not have.
public protocol SpeechRecognizing: Sendable {
    func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult
}
