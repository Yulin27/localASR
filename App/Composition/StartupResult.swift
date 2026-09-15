import DictationCore
import DictationDemo

/// Why the application cannot offer dictation. Every case is presentable to the user.
enum StartupIssue: Equatable, Sendable {
    /// This build has no real capture, recognition, or insertion adapters yet.
    case adaptersUnavailable
}

/// The long-lived services a ready application runs on. They live as long as the application.
struct ReadyServices: Sendable {
    let coordinator: DictationCoordinator

    /// Present only for an assembly that runs scripted demo scenarios.
    let demoScenarios: DemoScenarioSelector?
}

/// What an assembly produced.
///
/// The composition root wraps either case in an ``AppModel``, so the menu can present a
/// not-ready application as well as a ready one.
enum StartupResult: Sendable {
    case ready(ReadyServices)
    case notReady(StartupIssue)
}

/// Builds the application's dependencies, once, at launch.
@MainActor
protocol ApplicationAssembly {
    func makeStartup() -> StartupResult
}
