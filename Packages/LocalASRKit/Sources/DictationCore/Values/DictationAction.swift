import Foundation

/// A semantic user action.
///
/// Views and hotkey adapters forward these. They never encode workflow policy themselves:
/// deciding what a second activation means, or whether an activation is actionable at all,
/// belongs to the coordinator.
public enum DictationAction: Sendable, Equatable, CaseIterable {
    /// A complete shortcut activation. Starts a session when none is active, and stops
    /// recording when one is. Key release is not an action.
    case toggleRecording

    /// Abandon the active session and release everything it holds.
    case cancel

    /// Return a finished session to idle once the user has seen its outcome.
    case dismiss
}
