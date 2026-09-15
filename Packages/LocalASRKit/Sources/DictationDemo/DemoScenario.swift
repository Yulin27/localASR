import DictationCore
import Foundation
import Synchronization

/// One scripted way a demo session can end.
public enum DemoScenario: String, Sendable, Equatable, CaseIterable {
    /// Every stage succeeds and the text is inserted directly.
    case success
    /// The refiner times out, so the deterministic text becomes final.
    case refinementFallback
    /// Delivery degrades to the clipboard.
    case copiedOnly
    /// Recognition fails with a recoverable runtime failure.
    case recognitionFailure
    /// Voice activity detection finds no speech.
    case noSpeech
}

/// Chooses the scenario each demo session runs, and holds it fixed for that session.
///
/// The selection can change at any time, for example from a menu while a session is recording.
/// A change affects the next session only: a session's scenario is fixed the first time it is
/// looked up, and never changes afterwards.
///
/// Several ports are called without a session ID — capture, and voice activity detection, which
/// receives only the clip. So the scenario is read when recording starts, carried by the clip
/// capture produces, and bound to the session ID by the first port that receives one.
public final class DemoScenarioSelector: Sendable {
    /// Bindings kept for sessions that may still be running. Older ones are forgotten, which
    /// only matters for a session abandoned so long ago that its results are discarded anyway.
    static let retainedSessions = 16

    private struct State {
        var selection: DemoScenario
        var fixed: [(id: SessionID, scenario: DemoScenario)] = []
    }

    private let state: Mutex<State>

    public init(_ selection: DemoScenario = .success) {
        state = Mutex(State(selection: selection))
    }

    /// The scenario the next session will run.
    public var selection: DemoScenario {
        get { state.withLock { $0.selection } }
        set { state.withLock { $0.selection = newValue } }
    }

    /// The scenario fixed for `sessionID`.
    ///
    /// The first lookup fixes it: to `recorded`, the scenario its recording started under, when
    /// known, and otherwise to the current selection.
    public func scenario(for sessionID: SessionID, recorded: DemoScenario? = nil) -> DemoScenario {
        state.withLock { state in
            if let bound = state.fixed.first(where: { $0.id == sessionID }) {
                return bound.scenario
            }
            let scenario = recorded ?? state.selection
            state.fixed.append((sessionID, scenario))
            if state.fixed.count > Self.retainedSessions {
                state.fixed.removeFirst(state.fixed.count - Self.retainedSessions)
            }
            return scenario
        }
    }
}
