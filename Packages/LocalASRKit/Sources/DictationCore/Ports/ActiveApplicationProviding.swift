import Foundation

/// Captures the frontmost application and the insertion destination.
///
/// This is the first thing a session does, before any overlay or asynchronous work can
/// change focus, and the result is frozen for the whole session.
public protocol ActiveApplicationProviding: Sendable {
    /// Never throws. A missing Accessibility permission or a password field must not abort a
    /// recording — the user would lose their dictation over a delivery constraint. Failures
    /// are reported through ``TargetCaptureResult`` so delivery can degrade to copy-only
    /// while the session continues.
    func captureActiveTarget() async -> TargetCaptureResult
}
