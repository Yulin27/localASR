import Foundation

/// What the coordinator would do with each ``DictationAction`` right now.
///
/// Published on every ``SessionSnapshot`` so a view can title and enable its commands without
/// deciding anything. A view must not derive this from the phase: the coordinator decides
/// `toggleRecording` and `cancel` from the session it has in flight, and that differs from the
/// published phase while a finished session is still cleaning up (ADR 0005).
public struct AcceptedActions: Sendable, Equatable {
    /// What a `toggleRecording` activation would do.
    public enum Toggle: Sendable, Equatable {
        /// No session is in flight, so an activation starts one.
        case start
        /// A session is preparing or recording, so an activation ends recording.
        case stop
        /// Recording has already stopped and processing is under way. An activation does
        /// nothing.
        case ignored
    }

    public let toggle: Toggle

    /// Whether `cancel` would abandon a session. True exactly while one is in flight.
    public let cancel: Bool

    /// Whether `dismiss` would return a finished session to idle.
    public let dismiss: Bool

    public init(toggle: Toggle, cancel: Bool, dismiss: Bool) {
        self.toggle = toggle
        self.cancel = cancel
        self.dismiss = dismiss
    }

    /// Accepts nothing. What a coordinator that has shut down publishes.
    public static let nothing = AcceptedActions(toggle: .ignored, cancel: false, dismiss: false)

    /// What a coordinator accepts in `phase` once no session cleanup is outstanding.
    ///
    /// A default for snapshots built outside the coordinator, such as previews and tests. The
    /// coordinator never uses it: it stamps every snapshot it publishes from its own state.
    public init(settledIn phase: DictationPhase) {
        switch phase {
        case .idle:
            self.init(toggle: .start, cancel: false, dismiss: false)
        case .preparing, .recording:
            self.init(toggle: .stop, cancel: true, dismiss: false)
        case .transcribing, .normalizing, .refining, .inserting:
            self.init(toggle: .ignored, cancel: true, dismiss: false)
        case .completed, .cancelled, .failed:
            self.init(toggle: .start, cancel: false, dismiss: true)
        }
    }

    /// Whether `action` would change anything.
    public func accepts(_ action: DictationAction) -> Bool {
        switch action {
        case .toggleRecording: toggle != .ignored
        case .cancel: cancel
        case .dismiss: dismiss
        }
    }
}
