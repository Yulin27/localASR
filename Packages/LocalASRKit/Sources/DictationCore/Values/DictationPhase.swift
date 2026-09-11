import Foundation

/// The user-visible lifecycle of one dictation session.
///
/// Voice activity detection shares the `.transcribing` phase. The lifecycle does not give it
/// a step of its own, and nothing user-visible changes between trimming silence and running
/// recognition. A voice-activity failure is reported at `.transcribing`.
public enum DictationPhase: String, Sendable, Equatable, Codable, CaseIterable {
    case idle
    case preparing
    case recording
    case transcribing
    case normalizing
    case refining
    case inserting
    case completed
    case cancelled
    case failed

    /// A finished phase. Its outcome stays visible until the user dismisses it or starts
    /// another session.
    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed: true
        default: false
        }
    }

    /// A session is in flight. Only one may be active at a time.
    public var isActive: Bool { self != .idle && !isTerminal }

    public func canTransition(to next: DictationPhase) -> Bool {
        Self.allowedTransitions[self, default: []].contains(next)
    }

    /// The complete transition truth table. A transition that is absent is a defect rather
    /// than a state the coordinator may reach.
    ///
    /// - `normalizing -> inserting` exists for `.deterministicOnly`, which skips refinement.
    /// - `completed`/`cancelled`/`failed -> preparing` exists because pressing the shortcut
    ///   again from a finished session starts a new one.
    static let allowedTransitions: [DictationPhase: Set<DictationPhase>] = [
        .idle: [.preparing],
        .preparing: [.recording, .cancelled, .failed],
        .recording: [.transcribing, .cancelled, .failed],
        .transcribing: [.normalizing, .cancelled, .failed],
        .normalizing: [.refining, .inserting, .cancelled, .failed],
        .refining: [.inserting, .cancelled, .failed],
        .inserting: [.completed, .cancelled, .failed],
        .completed: [.idle, .preparing],
        .cancelled: [.idle, .preparing],
        .failed: [.idle, .preparing],
    ]
}
