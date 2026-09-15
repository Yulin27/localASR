import DictationCore
import DictationDemo
import Testing

@testable import LocalASR

@MainActor
@Suite("Composition root")
struct CompositionTests {
    @Test("The production assembly reports that adapters are unavailable")
    func productionIsNotReady() {
        let startup = ProductionAssembly().makeStartup()
        guard case .notReady(let issue) = startup else {
            Issue.record("The production assembly must not report ready before real adapters exist")
            return
        }
        #expect(issue == .adaptersUnavailable)
        #expect(AppModel(startup: startup).readiness == .notReady(.adaptersUnavailable))
    }

    #if DEBUG
    @Test("The demo assembly yields an idle coordinator and demo scenarios")
    func demoIsReadyAndIdle() async throws {
        let services = try #require(DemoAssembly().makeStartup().services)
        let snapshot = await services.coordinator.currentSnapshot()

        #expect(snapshot.phase == .idle)
        #expect(snapshot.acceptedActions.toggle == .start)
        #expect(services.demoScenarios?.selection == .success)
        await services.coordinator.shutdown()
    }
    #endif

    @Test("A test host selects the test assembly")
    func testHostSelectsTestAssembly() {
        let kind = CompositionRoot.assemblyKind(
            environment: ["XCTestConfigurationFilePath": "/tmp/session.xctestconfiguration"]
        )
        #expect(kind == .test)
    }

    @Test("An ordinary launch selects demo in Debug and production in Release")
    func ordinaryLaunchSelectsByConfiguration() {
        let kind = CompositionRoot.assemblyKind(environment: [:])
        #if DEBUG
        #expect(kind == .demo)
        #else
        #expect(kind == .production)
        #endif
    }

    @Test("Termination shuts the coordinator down")
    func terminationShutsDown() async throws {
        let startup = TestAssembly().makeStartup()
        let coordinator = try #require(startup.services?.coordinator)
        let delegate = AppDelegate(model: AppModel(startup: startup))
        delegate.model.start()

        await delegate.prepareForTermination()

        // A coordinator that has shut down accepts nothing (ADR 0005).
        #expect(await coordinator.currentSnapshot().acceptedActions == .nothing)
        delegate.model.send(.toggleRecording)
        #expect(await coordinator.currentSnapshot().phase == .idle)
    }
}
