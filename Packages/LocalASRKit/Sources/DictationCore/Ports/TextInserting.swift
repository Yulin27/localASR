import Foundation

/// A request to deliver text to a destination.
public struct InsertionRequest: Sendable {
    public let sessionID: SessionID

    /// The final text. Whatever happens next, the caller still holds it.
    public let text: String

    /// The destination frozen at session start, or `nil` when it could not be resolved —
    /// in which case delivery degrades to copy-only.
    public let target: InsertionTarget?

    public init(sessionID: SessionID, text: String, target: InsertionTarget?) {
        self.sessionID = sessionID
        self.text = text
        self.target = target
    }
}

/// Delivers final text to the frozen destination.
///
/// The implementation owns the delivery ladder — Accessibility write, then a clipboard
/// transaction with a synthetic paste, then copy-only — and reports which rung it reached.
public protocol TextInserting: Sendable {
    /// Delivers the text and reports what actually happened.
    ///
    /// Never throws. A thrown error would discard the structured outcome, and with it the
    /// guarantee that a failed insertion still leaves the text copyable.
    func insert(_ request: InsertionRequest) async -> InsertionOutcome
}
