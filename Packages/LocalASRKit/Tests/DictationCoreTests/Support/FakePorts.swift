import Foundation

@testable import DictationCore

// MARK: - Audio

/// An inspectable clip.
///
/// Discards are counted rather than left to ARC, so a test can prove the coordinator
/// released the clip on a given path instead of merely dropping the last reference.
actor FakeAudioClip: AudioClip {
    nonisolated let metadata: AudioClipMetadata
    private let samples: [Float]
    private(set) var discardCount = 0
    private(set) var loadCount = 0

    init(frameCount: Int = 16_000, sampleRate: Double = 16_000) {
        metadata = AudioClipMetadata(sampleRate: sampleRate, frameCount: frameCount)
        samples = Array(repeating: 0.1, count: frameCount)
    }

    func loadSamples() async throws -> AudioSamples {
        loadCount += 1
        return AudioSamples(samples: samples, sampleRate: metadata.sampleRate)
    }

    func discard() async {
        discardCount += 1
    }
}

actor FakeAudioCapturing: AudioCapturing {
    enum Event: Sendable, Equatable {
        case prepare, start, stop, cancel
    }

    private(set) var events: [Event] = []
    let clip: FakeAudioClip

    var prepareResponse: FakeResponse<Void> = .ok
    var startResponse: FakeResponse<Void> = .ok
    var stopResponse: FakeResponse<Void> = .ok

    private let prepareLatch: Latch?
    private let startLatch: Latch?
    private let stopLatch: Latch?

    init(
        clip: FakeAudioClip,
        prepareLatch: Latch? = nil,
        startLatch: Latch? = nil,
        stopLatch: Latch? = nil
    ) {
        self.clip = clip
        self.prepareLatch = prepareLatch
        self.startLatch = startLatch
        self.stopLatch = stopLatch
    }

    func setPrepareResponse(_ response: FakeResponse<Void>) {
        prepareResponse = response
    }

    func setStartResponse(_ response: FakeResponse<Void>) {
        startResponse = response
    }

    func setStopResponse(_ response: FakeResponse<Void>) {
        stopResponse = response
    }

    func prepare() async throws {
        events.append(.prepare)
        await prepareLatch?.arriveAndWait()
        _ = try prepareResponse.resolve()
    }

    func start() async throws {
        events.append(.start)
        await startLatch?.arriveAndWait()
        _ = try startResponse.resolve()
    }

    func stop() async throws -> any AudioClip {
        events.append(.stop)
        await stopLatch?.arriveAndWait()
        _ = try stopResponse.resolve()
        return clip
    }

    /// Deliberately not latch-gated: it is a cleanup call, and parking it would deadlock
    /// teardown.
    func cancel() async {
        events.append(.cancel)
    }

    var cancelCount: Int { events.count(where: { $0 == .cancel }) }
    var stopCount: Int { events.count(where: { $0 == .stop }) }
}

// MARK: - Voice activity

actor FakeVoiceActivityDetector: VoiceActivityDetecting {
    var response: FakeResponse<VoiceActivityOutcome> = .value(
        .speech(AudioSegment(startFrame: 0, endFrame: 16_000))
    )
    private(set) var callCount = 0
    private let latch: Latch?

    init(latch: Latch? = nil) {
        self.latch = latch
    }

    func setResponse(_ response: FakeResponse<VoiceActivityOutcome>) {
        self.response = response
    }

    func trim(_ audio: any AudioClip) async throws -> VoiceActivityOutcome {
        callCount += 1
        await latch?.arriveAndWait()
        return try response.resolve()
    }
}

// MARK: - Recognition

actor FakeSpeechRecognizer: SpeechRecognizing {
    var response: FakeResponse<RecognitionResult> = .value(
        RecognitionResult(
            rawText: "raw text",
            engine: EngineIdentifier(name: "fake-asr", version: "1")
        )
    )
    private(set) var requests: [RecognitionRequest] = []
    private let latch: Latch?

    init(latch: Latch? = nil) {
        self.latch = latch
    }

    func setResponse(_ response: FakeResponse<RecognitionResult>) {
        self.response = response
    }

    func recognize(_ request: RecognitionRequest) async throws -> RecognitionResult {
        requests.append(request)
        await latch?.arriveAndWait()
        return try response.resolve()
    }

    var callCount: Int { requests.count }
}

// MARK: - Deterministic processing

actor FakeTextProcessor: DeterministicTextProcessing {
    var response: FakeResponse<NormalizedText> = .value(NormalizedText(text: "normalized text"))
    private(set) var requests: [TextProcessingRequest] = []
    private let latch: Latch?

    init(latch: Latch? = nil) {
        self.latch = latch
    }

    func setResponse(_ response: FakeResponse<NormalizedText>) {
        self.response = response
    }

    func process(_ request: TextProcessingRequest) async throws -> NormalizedText {
        requests.append(request)
        await latch?.arriveAndWait()
        return try response.resolve()
    }

    var callCount: Int { requests.count }
}

// MARK: - Refinement

actor FakeRefiner: TextRefining {
    var response: FakeResponse<RefinementOutput> = .value(
        RefinementOutput(
            text: "refined text",
            engine: EngineIdentifier(name: "fake-refiner", version: "1")
        )
    )
    private(set) var requests: [RefinementRequest] = []
    private let latch: Latch?

    init(latch: Latch? = nil) {
        self.latch = latch
    }

    func setResponse(_ response: FakeResponse<RefinementOutput>) {
        self.response = response
    }

    func refine(_ request: RefinementRequest) async throws -> RefinementOutput {
        requests.append(request)
        await latch?.arriveAndWait()
        return try response.resolve()
    }

    var callCount: Int { requests.count }
}

// MARK: - Insertion

actor FakeInserter: TextInserting {
    var outcome: InsertionOutcome = InsertionOutcome(
        delivery: .insertedDirectly,
        verification: .confirmed
    )
    private(set) var requests: [InsertionRequest] = []
    private let latch: Latch?

    init(latch: Latch? = nil) {
        self.latch = latch
    }

    func setOutcome(_ outcome: InsertionOutcome) {
        self.outcome = outcome
    }

    func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        requests.append(request)
        await latch?.arriveAndWait()
        return outcome
    }

    var callCount: Int { requests.count }
}

// MARK: - Target capture

actor FakeTargetProvider: ActiveApplicationProviding {
    var result: TargetCaptureResult
    private(set) var callCount = 0
    private let latch: Latch?

    init(
        result: TargetCaptureResult = .captured(
            InsertionTarget(
                application: ActiveApplication(
                    processIdentifier: 501,
                    bundleIdentifier: "com.example.editor",
                    localizedName: "Editor"
                ),
                elementToken: "focused-field"
            )
        ),
        latch: Latch? = nil
    ) {
        self.result = result
        self.latch = latch
    }

    func captureActiveTarget() async -> TargetCaptureResult {
        callCount += 1
        await latch?.arriveAndWait()
        return result
    }
}

// MARK: - Mode resolution

struct FakeModeResolver: ModeResolving {
    var modes: [String: RefinementMode] = [:]

    func resolveMode(
        for target: InsertionTarget?,
        default defaultMode: RefinementMode
    ) -> RefinementMode {
        guard let bundleID = target?.application.bundleIdentifier,
              let mode = modes[bundleID]
        else {
            return defaultMode
        }
        return mode
    }
}

// MARK: - Settings

actor FakeSettingsProvider: DictationSettingsProviding {
    private(set) var settings: DictationSettings
    private(set) var callCount = 0
    private let latch: Latch?

    init(settings: DictationSettings = .standard, latch: Latch? = nil) {
        self.settings = settings
        self.latch = latch
    }

    func currentSettings() async -> DictationSettings {
        callCount += 1
        await latch?.arriveAndWait()
        return settings
    }

    func update(_ settings: DictationSettings) {
        self.settings = settings
    }
}

// MARK: - History

actor FakeHistoryStore: HistoryStoring {
    private(set) var records: [SessionRecord] = []
    var writeError: Error?
    private let latch: Latch?

    init(latch: Latch? = nil) {
        self.latch = latch
    }

    func setWriteError(_ error: Error?) {
        writeError = error
    }

    /// Honours cancellation, as a store doing file or database I/O would. A store that ignored
    /// it would hide a record written from a cancelled task and silently dropped.
    func record(_ record: SessionRecord) async throws {
        await latch?.arriveAndWait()
        try Task.checkCancellation()
        if let writeError { throw writeError }
        records.append(record)
    }

    func recent() async throws -> [SessionRecord] { records }
}
