import DictationCore
import DictationDemo
import Testing

@testable import LocalASR

@MainActor
@Suite("Application model")
struct AppModelTests {
    @Test("The model reflects each snapshot the coordinator streams")
    func reflectsStreamedSnapshots() async throws {
        let assembly = TestAssembly(scenario: .success)
        let model = AppModel(startup: assembly.makeStartup())
        model.start()

        #expect(model.snapshot.phase == .idle)

        model.send(.toggleRecording)
        try await advance(assembly.clock, until: "the model shows recording") {
            model.snapshot.phase == .recording
        }
        #expect(model.presentation.statusText == "Recording")

        model.send(.toggleRecording)
        try await advance(assembly.clock, until: "the model shows the finished session") {
            model.snapshot.phase.isTerminal
        }
        #expect(model.snapshot.phase == .completed)
        #expect(model.presentation.statusText == "Inserted")

        model.send(.dismiss)
        try await advance(assembly.clock, until: "the model shows idle") {
            model.snapshot.phase == .idle
        }
        await model.shutdown()
    }

    @Test("Actions reach the coordinator in the order they were sent")
    func forwardsActionsInOrder() async throws {
        let assembly = TestAssembly(scenario: .success)
        let model = AppModel(startup: assembly.makeStartup())
        model.start()

        // Sent back to back. Delivered out of order, the cancel would arrive first, do nothing,
        // and leave a session recording.
        model.send(.toggleRecording)
        model.send(.cancel)

        try await advance(assembly.clock, until: "the session was cancelled") {
            model.snapshot.phase == .cancelled
        }
        #expect(model.snapshot.acceptedActions.dismiss)
        await model.shutdown()
    }

    @Test("Selecting a demo scenario changes what the next session does")
    func selectsDemoScenario() async throws {
        let assembly = TestAssembly(scenario: .success)
        let model = AppModel(startup: assembly.makeStartup())
        model.start()

        #expect(model.demoScenario == .success)
        model.selectDemoScenario(.noSpeech)
        #expect(model.demoScenario == .noSpeech)
        #expect(assembly.scenarios.selection == .noSpeech)

        model.send(.toggleRecording)
        try await advance(assembly.clock, until: "recording") { model.snapshot.phase == .recording }
        model.send(.toggleRecording)
        try await advance(assembly.clock, until: "the session ended") {
            model.snapshot.phase.isTerminal
        }
        #expect(model.snapshot.failure?.category == .noSpeechDetected)
        #expect(model.presentation.statusText == "No Speech Detected")
        await model.shutdown()
    }

    @Test("Observation ends when the coordinator shuts down", .timeLimit(.minutes(1)))
    func observationEndsOnShutdown() async throws {
        let startup = TestAssembly().makeStartup()
        let coordinator = try #require(startup.services?.coordinator)
        let model = AppModel(startup: startup)
        model.start()

        await coordinator.shutdown()
        // Returns only because the snapshot stream finished.
        await model.observationEnded()
        await model.shutdown()
    }

    @Test("A model that is not ready ignores actions and offers no commands")
    func notReadyModel() async {
        let model = AppModel(startup: .notReady(.adaptersUnavailable))
        model.start()
        model.send(.toggleRecording)
        model.selectDemoScenario(.copiedOnly)

        #expect(model.readiness == .notReady(.adaptersUnavailable))
        #expect(model.demoScenario == nil)
        #expect(model.snapshot == .idle)
        #expect(model.presentation.commands.isEmpty)
        await model.shutdown()
    }
}
