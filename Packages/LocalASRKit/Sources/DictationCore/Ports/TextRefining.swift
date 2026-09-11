import Foundation

/// A request to rewrite one transcript for one mode.
public struct RefinementRequest: Sendable {
    public let sessionID: SessionID

    /// The deterministic text, passed as text to be cleaned up — never as a question to
    /// answer or an instruction to follow.
    public let text: String

    public let mode: RefinementMode
    public let language: LanguageHint

    public init(sessionID: SessionID, text: String, mode: RefinementMode, language: LanguageHint) {
        self.sessionID = sessionID
        self.text = text
        self.mode = mode
        self.language = language
    }
}

/// A refiner's raw output, before validation.
///
/// It is not final text. The coordinator runs it through the output guard, which lives
/// outside this protocol so a model adapter cannot certify its own result.
public struct RefinementOutput: Sendable, Equatable {
    public let text: String
    public let engine: EngineIdentifier

    public init(text: String, engine: EngineIdentifier) {
        self.text = text
        self.engine = engine
    }
}

/// Local, model-backed rewriting of one transcript.
///
/// The implementation receives isolated instructions, one transcript, and no conversation
/// history. Whether its output is acceptable is decided by the coordinator, not here.
public protocol TextRefining: Sendable {
    func refine(_ request: RefinementRequest) async throws -> RefinementOutput
}
