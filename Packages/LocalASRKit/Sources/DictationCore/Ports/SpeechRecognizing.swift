import Foundation

/// A request to transcribe one recording.
public struct RecognitionRequest: Sendable {
    public let sessionID: SessionID
    public let audio: any AudioClip

    /// The frame range voice activity selected, or `nil` to transcribe the whole clip — which
    /// is what happens when the detector was unavailable.
    public let speechSegment: AudioSegment?

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

    /// The language the recogniser actually used, when it reports one.
    public let language: LanguageHint?

    public let engine: EngineIdentifier

    public init(rawText: String, language: LanguageHint? = nil, engine: EngineIdentifier) {
        self.rawText = rawText
        self.language = language
        self.engine = engine
    }
}

/// Batch speech recognition.
///
/// Deliberately batch: v0.1 delivers one final result rather than streaming text into the
/// target, and streaming belongs in a separate protocol when it enters the accepted scope.
/// An implementation may chunk internally for long input while still returning one result.
public protocol SpeechRecognizing: Sendable {
    func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult
}
