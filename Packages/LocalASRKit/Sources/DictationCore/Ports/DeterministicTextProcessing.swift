import Foundation

/// A request to run the ordered deterministic transforms over raw recognition output.
public struct TextProcessingRequest: Sendable {
    public let sessionID: SessionID
    public let rawText: String
    public let language: LanguageHint

    /// The written form the destination wants. Deterministic punctuation and list handling
    /// depend on it, so it is supplied even when the model stage is switched off.
    public let mode: RefinementMode

    public init(
        sessionID: SessionID,
        rawText: String,
        language: LanguageHint,
        mode: RefinementMode
    ) {
        self.sessionID = sessionID
        self.rawText = rawText
        self.language = language
        self.mode = mode
    }
}

/// Ordered, versioned, model-free text cleanup.
///
/// This stage always runs and is expected to be cheap. It is the floor the pipeline falls
/// back to: when it fails, the raw text is used unchanged, and when refinement fails, its
/// output becomes the final text.
public protocol DeterministicTextProcessing: Sendable {
    func process(_ request: TextProcessingRequest) async throws -> NormalizedText
}
