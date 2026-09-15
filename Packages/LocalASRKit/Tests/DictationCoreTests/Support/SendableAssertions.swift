/// Fails to compile when `T` does not conform to `Sendable`.
///
/// Used by `SendableTests` so that adding a non-`Sendable` member to a value type, or a
/// non-`Sendable` port protocol, breaks the test target's compilation rather than surfacing
/// as a data race in a later phase.
func requireSendable<T: Sendable>(_ type: T.Type) {}
