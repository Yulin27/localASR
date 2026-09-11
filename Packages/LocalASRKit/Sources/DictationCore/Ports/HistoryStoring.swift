import Foundation

/// Stores the bounded recent-history list.
///
/// Storage is deliberately outside the core: preferences, history, and model state are
/// separate stores, and their backend is a later decision.
public protocol HistoryStoring: Sendable {
    /// Appends one completed session.
    ///
    /// May throw. A failure here never downgrades a dictation that already delivered: the
    /// text is on the clipboard or in the target, and the coordinator only reports the loss
    /// to metrics.
    func record(_ record: SessionRecord) async throws

    /// The stored records, newest first.
    func recent() async throws -> [SessionRecord]
}

/// Discards everything. For assemblies that do not surface history.
public struct NoopHistoryStore: HistoryStoring {
    public init() {}

    public func record(_ record: SessionRecord) async throws {}

    public func recent() async throws -> [SessionRecord] { [] }
}

public extension HistoryStoring where Self == NoopHistoryStore {
    static var noop: NoopHistoryStore { NoopHistoryStore() }
}
