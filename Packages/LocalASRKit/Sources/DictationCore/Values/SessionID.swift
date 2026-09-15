import Foundation

/// Identifies one dictation session.
///
/// Every asynchronous result in the pipeline is scoped to a session ID, so a callback that
/// arrives after cancellation, or after a replacement session has started, can be discarded
/// without inspecting its payload.
public struct SessionID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

/// Produces session identifiers.
///
/// Injected rather than generated inline. `DictationCore` must not reach for a global
/// random source, and tests need stable identifiers to assert against.
public struct SessionIDGenerator: Sendable {
    private let generate: @Sendable () -> SessionID

    public init(generate: @escaping @Sendable () -> SessionID) {
        self.generate = generate
    }

    public func next() -> SessionID { generate() }

    /// Random identifiers, for the application composition root.
    public static let random = SessionIDGenerator { SessionID() }
}
