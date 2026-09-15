import DictationCore
import Foundation

// Scripted implementations of the coordinator's ports.
//
// None of them touches a microphone, the pasteboard, the Accessibility API, the network, or a
// model. Each waits a scripted delay on an injected clock and returns what its session's
// scenario prescribes, so the application can play every state a real session reaches and tests
// can do the same on a clock they control.

/// How long each scripted stage takes.
public struct DemoTimings: Sendable, Equatable {
    public var targetCapture: Duration
    public var capturePrepare: Duration
    public var captureStart: Duration
    public var captureStop: Duration
    public var voiceActivity: Duration
    public var recognition: Duration
    public var normalization: Duration
    public var refinement: Duration
    public var insertion: Duration

    public init(
        targetCapture: Duration,
        capturePrepare: Duration,
        captureStart: Duration,
        captureStop: Duration,
        voiceActivity: Duration,
        recognition: Duration,
        normalization: Duration,
        refinement: Duration,
        insertion: Duration
    ) {
        self.targetCapture = targetCapture
        self.capturePrepare = capturePrepare
        self.captureStart = captureStart
        self.captureStop = captureStop
        self.voiceActivity = voiceActivity
        self.recognition = recognition
        self.normalization = normalization
        self.refinement = refinement
        self.insertion = insertion
    }

    /// Long enough to see each phase in a menu, short enough not to be tedious.
    public static let standard = DemoTimings(
        targetCapture: .milliseconds(20),
        capturePrepare: .milliseconds(300),
        captureStart: .milliseconds(100),
        captureStop: .milliseconds(100),
        voiceActivity: .milliseconds(400),
        recognition: .milliseconds(1_500),
        normalization: .milliseconds(500),
        refinement: .milliseconds(1_500),
        insertion: .milliseconds(500)
    )
}

/// The scripted text each stage produces.
enum DemoText {
    static let raw = "this is a demo dictation"
    static let normalized = "this is a demo dictation."
    static let refined = "This is a demo dictation."
    static let recognitionEngine = EngineIdentifier(name: "demo-recognizer", version: "1")
    static let refinementEngine = EngineIdentifier(name: "demo-refiner", version: "1")
    static let transform = TransformIdentifier(identifier: "demo.scripted", version: 1)
}

// MARK: - Audio

/// A recording with no samples behind it, carrying the scenario it was recorded under.
struct DemoAudioClip: AudioClip {
    static let sampleRate: Double = 16_000

    let metadata: AudioClipMetadata
    let scenario: DemoScenario

    func loadSamples() async throws -> AudioSamples {
        AudioSamples(
            samples: Array(repeating: 0, count: metadata.frameCount),
            sampleRate: metadata.sampleRate
        )
    }

    func discard() async {}
}

actor DemoAudioCapture<C: Clock>: AudioCapturing where C.Duration == Duration {
    private let clock: C
    private let timings: DemoTimings
    private let scenarios: DemoScenarioSelector
    private var recording: (startedAt: C.Instant, scenario: DemoScenario)?

    init(clock: C, timings: DemoTimings, scenarios: DemoScenarioSelector) {
        self.clock = clock
        self.timings = timings
        self.scenarios = scenarios
    }

    func prepare() async throws {
        try await clock.sleep(for: timings.capturePrepare)
    }

    func start() async throws {
        try await clock.sleep(for: timings.captureStart)
        // Read once, here: the session's scenario is fixed when its recording begins.
        recording = (clock.now, scenarios.selection)
    }

    func stop() async throws -> any AudioClip {
        guard let recording else {
            throw DictationFailure(
                stage: .recording,
                category: .deviceUnavailable,
                recoverability: .recoverable,
                diagnosticCode: "demo.capture.notRecording"
            )
        }
        self.recording = nil
        let elapsed = recording.startedAt.duration(to: clock.now)
        try await clock.sleep(for: timings.captureStop)
        return DemoAudioClip(
            metadata: AudioClipMetadata(
                sampleRate: DemoAudioClip.sampleRate,
                frameCount: max(0, Int(elapsed.demoSeconds * DemoAudioClip.sampleRate)),
                origin: .testFixture
            ),
            scenario: recording.scenario
        )
    }

    func cancel() async {
        recording = nil
    }
}

// MARK: - Pipeline stages

struct DemoVoiceActivityDetector<C: Clock>: VoiceActivityDetecting where C.Duration == Duration {
    let clock: C
    let timings: DemoTimings
    let scenarios: DemoScenarioSelector

    func trim(_ audio: any AudioClip) async throws -> VoiceActivityOutcome {
        try await clock.sleep(for: timings.voiceActivity)
        let scenario = (audio as? DemoAudioClip)?.scenario ?? scenarios.selection
        if scenario == .noSpeech {
            return .noSpeech
        }
        return .speech(AudioSegment(startFrame: 0, endFrame: audio.metadata.frameCount))
    }
}

struct DemoSpeechRecognizer<C: Clock>: SpeechRecognizing where C.Duration == Duration {
    let clock: C
    let timings: DemoTimings
    let scenarios: DemoScenarioSelector

    func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
        let scenario = scenarios.scenario(
            for: request.sessionID,
            recorded: (request.audio as? DemoAudioClip)?.scenario
        )
        try await clock.sleep(for: timings.recognition)
        if scenario == .recognitionFailure {
            throw DictationFailure(
                stage: .transcribing,
                category: .runtimeFailure,
                recoverability: .recoverable,
                diagnosticCode: "demo.recognition.scripted"
            )
        }
        return RecognitionResult(rawText: DemoText.raw, engine: DemoText.recognitionEngine)
    }
}

struct DemoTextProcessor<C: Clock>: DeterministicTextProcessing where C.Duration == Duration {
    let clock: C
    let timings: DemoTimings

    func process(_ request: TextProcessingRequest) async throws -> NormalizedText {
        try await clock.sleep(for: timings.normalization)
        return NormalizedText(text: DemoText.normalized, transforms: [DemoText.transform])
    }
}

struct DemoRefiner<C: Clock>: TextRefining where C.Duration == Duration {
    let clock: C
    let timings: DemoTimings
    let scenarios: DemoScenarioSelector

    func refine(_ request: RefinementRequest) async throws -> RefinementOutput {
        let scenario = scenarios.scenario(for: request.sessionID)
        try await clock.sleep(for: timings.refinement)
        if scenario == .refinementFallback {
            throw DictationFailure(
                stage: .refining,
                category: .timeout,
                recoverability: .recoverable,
                diagnosticCode: "demo.refinement.scripted"
            )
        }
        return RefinementOutput(text: DemoText.refined, engine: DemoText.refinementEngine)
    }
}

struct DemoInserter<C: Clock>: TextInserting where C.Duration == Duration {
    let clock: C
    let timings: DemoTimings
    let scenarios: DemoScenarioSelector

    func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        let scenario = scenarios.scenario(for: request.sessionID)
        // Insertion never throws, so a cancelled wait simply ends early. The coordinator checks
        // for the cancellation itself once this returns.
        try? await clock.sleep(for: timings.insertion)
        if scenario == .copiedOnly {
            return .copiedOnly(.targetUnavailable)
        }
        return InsertionOutcome(delivery: .insertedDirectly, verification: .confirmed)
    }
}

// MARK: - Context and bookkeeping

struct DemoTargetProvider<C: Clock>: ActiveApplicationProviding where C.Duration == Duration {
    static var target: InsertionTarget {
        InsertionTarget(
            application: ActiveApplication(
                processIdentifier: 0,
                bundleIdentifier: "io.github.yulin27.LocalASR.demo-target",
                localizedName: "Demo Target"
            ),
            elementToken: "demo-field"
        )
    }

    let clock: C
    let timings: DemoTimings

    func captureActiveTarget() async -> TargetCaptureResult {
        try? await clock.sleep(for: timings.targetCapture)
        return .captured(Self.target)
    }
}

/// Timestamps read from the injected clock, so stage timings follow a manual clock in tests.
struct DemoTimeSource<C: Clock>: TimeSource where C.Duration == Duration {
    private let clock: C
    private let origin: C.Instant
    private let originDate: Date

    init(clock: C, originDate: Date) {
        self.clock = clock
        self.origin = clock.now
        self.originDate = originDate
    }

    func now() -> Timestamp {
        let elapsed = origin.duration(to: clock.now).demoSeconds
        return Timestamp(date: originDate.addingTimeInterval(elapsed), uptime: elapsed)
    }
}

extension Duration {
    var demoSeconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}
