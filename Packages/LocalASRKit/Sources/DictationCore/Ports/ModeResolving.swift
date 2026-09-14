import Foundation

/// Chooses the written form a destination wants.
///
/// Synchronous and pure: it consults typed mode data rather than performing work, and it is
/// called once per session so the resolved mode can be frozen before focus can change.
public protocol ModeResolving: Sendable {
    /// Resolves the mode for a session's source application.
    ///
    /// The application rather than the destination: `Spec.md` keys per-application modes on the
    /// frontmost bundle identifier, and reading which application is frontmost needs no
    /// Accessibility permission. Taking an `InsertionTarget` would silently drop back to the
    /// default for every session whose focused element could not be resolved — exactly the
    /// sessions where the destination is a password field, or the permission is not yet
    /// granted.
    ///
    /// - Parameters:
    ///   - application: The frontmost application frozen at recording start, or `nil` when it
    ///     could not be read.
    ///   - defaultMode: The user's default, used when no per-application rule matches.
    func resolveMode(
        for application: ActiveApplication?,
        default defaultMode: RefinementMode
    ) -> RefinementMode
}
