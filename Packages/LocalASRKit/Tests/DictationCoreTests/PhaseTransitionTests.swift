import Testing

@testable import DictationCore

@Suite("Phase transition table")
struct PhaseTransitionTests {
    @Test("idle is the only phase that can start a session")
    func onlyIdleStartsASession() {
        let canStart = DictationPhase.allCases.filter { $0.canTransition(to: .preparing) }
        #expect(Set(canStart) == [.idle, .completed, .cancelled, .failed])
    }

    @Test("Every active phase can be cancelled and can fail")
    func activePhasesCanAbort() {
        for phase in DictationPhase.allCases where phase.isActive {
            #expect(phase.canTransition(to: .cancelled), "\(phase) cannot be cancelled")
            #expect(phase.canTransition(to: .failed), "\(phase) cannot fail")
        }
    }

    @Test("No phase transitions to itself")
    func noSelfTransitions() {
        for phase in DictationPhase.allCases {
            #expect(!phase.canTransition(to: phase), "\(phase) transitions to itself")
        }
    }

    @Test("Terminal phases only dismiss or start a new session")
    func terminalPhasesOnlyDismissOrRestart() {
        for phase in DictationPhase.allCases where phase.isTerminal {
            let allowed = DictationPhase.allCases.filter { phase.canTransition(to: $0) }
            #expect(Set(allowed) == [.idle, .preparing], "\(phase) allows \(allowed)")
        }
    }

    @Test("The batch happy path is a legal chain")
    func happyPathIsLegal() {
        let path: [DictationPhase] = [
            .idle, .preparing, .recording, .transcribing, .normalizing, .refining, .inserting,
            .completed, .idle,
        ]
        assertLegal(path)
    }

    @Test("Disabling refinement skips the refining phase")
    func deterministicOnlySkipsRefining() {
        let path: [DictationPhase] = [
            .idle, .preparing, .recording, .transcribing, .normalizing, .inserting, .completed,
        ]
        assertLegal(path)
    }

    @Test("Every active phase can be reached from idle and then cancelled back to idle")
    func cancellationPathsAreLegal() {
        let order: [DictationPhase] = [
            .preparing, .recording, .transcribing, .normalizing, .refining, .inserting,
        ]
        for index in order.indices {
            var path = Array(order.prefix(index + 1))
            path.insert(.idle, at: 0)
            path.append(contentsOf: [.cancelled, .idle])
            assertLegal(path)
        }
    }

    @Test("Transitions that would skip a stage or leave the lifecycle are rejected")
    func illegalTransitions() {
        #expect(!DictationPhase.idle.canTransition(to: .completed))
        #expect(!DictationPhase.idle.canTransition(to: .recording))
        #expect(!DictationPhase.recording.canTransition(to: .normalizing))
        #expect(!DictationPhase.transcribing.canTransition(to: .refining))
        #expect(!DictationPhase.transcribing.canTransition(to: .inserting))
        #expect(!DictationPhase.inserting.canTransition(to: .refining))
        #expect(!DictationPhase.completed.canTransition(to: .recording))
        #expect(!DictationPhase.completed.canTransition(to: .failed))
        #expect(!DictationPhase.cancelled.canTransition(to: .completed))
    }

    @Test("Active and terminal classification")
    func classification() {
        #expect(!DictationPhase.idle.isActive)
        #expect(!DictationPhase.idle.isTerminal)
        for phase in [DictationPhase.completed, .cancelled, .failed] {
            #expect(phase.isTerminal)
            #expect(!phase.isActive)
        }
        for phase in DictationPhase.allCases where phase != .idle && !phase.isTerminal {
            #expect(phase.isActive)
        }
    }

    private func assertLegal(
        _ path: [DictationPhase],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for (current, next) in zip(path, path.dropFirst()) {
            #expect(
                current.canTransition(to: next),
                "\(current) -> \(next) is not allowed",
                sourceLocation: sourceLocation
            )
        }
    }
}
