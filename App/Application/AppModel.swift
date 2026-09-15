import DictationCore
import DictationDemo
import Observation

/// The application-level observable state.
///
/// It holds the startup result and the coordinator's latest snapshot, and nothing else about the
/// workflow: snapshots arrive from the coordinator, and actions are forwarded to it in the order
/// they were sent. Deciding what an action means stays in the coordinator.
@MainActor
@Observable
final class AppModel {
    enum Readiness: Equatable {
        case ready
        case notReady(StartupIssue)
    }

    let readiness: Readiness

    /// The coordinator's most recent snapshot. `.idle` until the first one arrives.
    private(set) var snapshot: SessionSnapshot = .idle

    /// The scenario the next demo session runs, or `nil` when the assembly runs no scenarios.
    private(set) var demoScenario: DemoScenario?

    @ObservationIgnored private let coordinator: DictationCoordinator?
    @ObservationIgnored private let demoScenarios: DemoScenarioSelector?
    @ObservationIgnored private let actions: AsyncStream<DictationAction>
    @ObservationIgnored private let actionSink: AsyncStream<DictationAction>.Continuation
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var forwarding: Task<Void, Never>?

    init(startup: StartupResult) {
        switch startup {
        case .ready(let services):
            readiness = .ready
            coordinator = services.coordinator
            demoScenarios = services.demoScenarios
            demoScenario = services.demoScenarios?.selection
        case .notReady(let issue):
            readiness = .notReady(issue)
            coordinator = nil
            demoScenarios = nil
            demoScenario = nil
        }
        // One ordered queue rather than a task per action: a Stop followed at once by a Cancel
        // must reach the coordinator in that order.
        let queue = AsyncStream.makeStream(of: DictationAction.self)
        actions = queue.stream
        actionSink = queue.continuation
    }

    var presentation: MenuBarPresentation {
        switch readiness {
        case .ready: MenuBarPresentation(snapshot: snapshot)
        case .notReady(let issue): MenuBarPresentation(issue: issue)
        }
    }

    /// Begins observing snapshots and forwarding actions. Idempotent.
    func start() {
        guard let coordinator, observation == nil else { return }

        observation = Task { [weak self] in
            for await snapshot in await coordinator.snapshots() {
                guard let self else { return }
                self.snapshot = snapshot
            }
        }

        let actions = self.actions
        forwarding = Task {
            for await action in actions {
                await coordinator.handle(action)
            }
        }
    }

    /// Forwards a semantic action. Does nothing when the application is not ready.
    func send(_ action: DictationAction) {
        guard coordinator != nil else { return }
        actionSink.yield(action)
    }

    /// Chooses the scenario the next demo session runs.
    func selectDemoScenario(_ scenario: DemoScenario) {
        guard let demoScenarios else { return }
        demoScenarios.selection = scenario
        demoScenario = scenario
    }

    /// Shuts the coordinator down, and returns once observation and forwarding have ended.
    ///
    /// Actions still queued are dropped rather than delivered: a coordinator that has shut down
    /// ignores them, and starting a session on the way out would open the microphone for nobody.
    func shutdown() async {
        actionSink.finish()
        await coordinator?.shutdown()
        await forwarding?.value
        await observation?.value
    }

    /// Returns once snapshot observation has ended, which happens when the coordinator shuts down.
    func observationEnded() async {
        await observation?.value
    }
}
