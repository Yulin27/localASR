import DictationCore
import Foundation

/// Builds a coordinator's dependencies entirely from scripted demo adapters.
public enum DemoDependencies {
    /// - Parameters:
    ///   - scenarios: Chooses what each session does. Keep a reference to change the selection.
    ///   - clock: Paces every scripted delay. `ContinuousClock` for the application, a
    ///     ``ManualClock`` for tests.
    ///   - timings: How long each stage takes.
    ///   - settings: The settings every session freezes.
    public static func make<C: Clock>(
        scenarios: DemoScenarioSelector,
        clock: C,
        timings: DemoTimings = .standard,
        settings: DictationSettings = .standard
    ) -> DictationCoordinator.Dependencies where C.Duration == Duration {
        DictationCoordinator.Dependencies(
            capture: DemoAudioCapture(clock: clock, timings: timings, scenarios: scenarios),
            voiceActivity: DemoVoiceActivityDetector(
                clock: clock,
                timings: timings,
                scenarios: scenarios
            ),
            recognition: DemoSpeechRecognizer(clock: clock, timings: timings, scenarios: scenarios),
            textProcessing: DemoTextProcessor(clock: clock, timings: timings),
            refiner: DemoRefiner(clock: clock, timings: timings, scenarios: scenarios),
            inserter: DemoInserter(clock: clock, timings: timings, scenarios: scenarios),
            targetProvider: DemoTargetProvider(clock: clock, timings: timings),
            modeResolver: BundleIDModeResolver(),
            settings: StaticSettingsProvider(settings),
            history: NoopHistoryStore(),
            metrics: NoopMetricsRecorder(),
            time: DemoTimeSource(clock: clock, originDate: Date())
        )
    }
}
