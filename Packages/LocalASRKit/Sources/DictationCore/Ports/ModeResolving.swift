import Foundation

/// Chooses the written form a destination wants.
///
/// Synchronous and pure: it consults typed mode data rather than performing work, and it is
/// called once per session so the resolved mode can be frozen before focus can change.
public protocol ModeResolving: Sendable {
    /// Resolves the mode for a session's destination.
    ///
    /// - Parameters:
    ///   - target: The frozen insertion destination, or `nil` when none was captured.
    ///   - defaultMode: The user's default, used when no per-application rule matches.
    func resolveMode(
        for target: InsertionTarget?,
        default defaultMode: RefinementMode
    ) -> RefinementMode
}
