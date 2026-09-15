import DictationCore
import DictationDemo

/// The Release assembly.
///
/// Reports not ready until Phase 3 supplies real adapters. It never falls back to the demo
/// adapters: scripted results must not pose as a working build.
struct ProductionAssembly: ApplicationAssembly {
    func makeStartup() -> StartupResult {
        .notReady(.adaptersUnavailable)
    }
}

#if DEBUG
/// The Debug assembly: a real coordinator over scripted adapters, paced in real time.
struct DemoAssembly: ApplicationAssembly {
    var initialScenario: DemoScenario = .success

    func makeStartup() -> StartupResult {
        let scenarios = DemoScenarioSelector(initialScenario)
        let coordinator = DictationCoordinator(
            dependencies: DemoDependencies.make(scenarios: scenarios, clock: ContinuousClock())
        )
        return .ready(ReadyServices(coordinator: coordinator, demoScenarios: scenarios))
    }
}
#endif

/// The assembly for a test host: scripted adapters on a clock only a test moves.
///
/// Launched as the host of `LocalASRTests`, the application therefore sits idle and inert, and a
/// test that builds its own instance drives every delay deterministically.
struct TestAssembly: ApplicationAssembly {
    let clock: ManualClock
    let scenarios: DemoScenarioSelector

    init(scenario: DemoScenario = .success) {
        clock = ManualClock()
        scenarios = DemoScenarioSelector(scenario)
    }

    func makeStartup() -> StartupResult {
        let coordinator = DictationCoordinator(
            dependencies: DemoDependencies.make(scenarios: scenarios, clock: clock)
        )
        return .ready(ReadyServices(coordinator: coordinator, demoScenarios: scenarios))
    }
}
