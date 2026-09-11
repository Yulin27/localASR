import Foundation
import Testing

@testable import DictationCore

@Suite("Session record and metrics")
struct SessionRecordTests {
    private let sessionID = SessionID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    )

    @Test("A history record preserves all three text stages")
    func recordPreservesTextStages() {
        let record = SessionRecord(
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceBundleIdentifier: "com.example.editor",
            languageHint: .french,
            mode: .message,
            transcript: Transcript(rawText: "raw", normalizedText: "norm", finalText: "final"),
            recognitionEngine: EngineIdentifier(name: "asr", version: "0.6b", revision: "abc123"),
            refinementEngine: EngineIdentifier(name: "refiner", version: "4b", revision: "def456"),
            timings: [StageTiming(phase: .transcribing, duration: .milliseconds(220))],
            fallbackReasons: [.refinementTimedOut],
            insertion: InsertionOutcome(delivery: .insertedDirectly, verification: .confirmed),
            zeroEditFeedback: ZeroEditFeedback(
                judgement: .unchanged,
                recordedAt: Date(timeIntervalSince1970: 1_700_000_060)
            )
        )

        #expect(record.transcript.rawText == "raw")
        #expect(record.transcript.normalizedText == "norm")
        #expect(record.transcript.finalText == "final")
        #expect(record.mode == .message)
        #expect(record.languageHint == .french)
        #expect(record.recognitionEngine?.revision == "abc123")
        #expect(record.refinementEngine?.revision == "def456")
        #expect(record.fallbackReasons == [.refinementTimedOut])
        #expect(record.insertion?.verification == .confirmed)
        #expect(record.zeroEditFeedback?.judgement == .unchanged)
    }

    @Test("A record marks a session with refinement disabled by omitting the mode")
    func recordOmitsModeWhenRefinementIsDisabled() {
        let record = SessionRecord(
            sessionID: sessionID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            languageHint: .automatic,
            transcript: Transcript(rawText: "raw", normalizedText: "norm", finalText: "norm")
        )

        #expect(record.mode == nil)
        #expect(record.refinementEngine == nil)
    }

    @Test("Metrics report counts and durations rather than text")
    func metricsReportCounts() {
        // SessionMetrics has no text-valued field at all; this asserts the shape of what it
        // does carry, which is what any future log or export is allowed to contain.
        let metrics = SessionMetrics(
            sessionID: sessionID,
            outcome: .completed,
            timings: [StageTiming(phase: .recording, duration: .seconds(4))],
            fallbacks: [.refinementEmptyOutput],
            audioDuration: .seconds(4),
            rawCharacterCount: 12,
            finalCharacterCount: 27
        )

        #expect(metrics.rawCharacterCount == 12)
        #expect(metrics.finalCharacterCount == 27)
        #expect(metrics.audioDuration == .seconds(4))
        #expect(metrics.failureCategory == nil)
        #expect(metrics.failureStage == nil)
    }

    @Test("Metrics attribute a failure to its category and stage")
    func metricsAttributeFailures() {
        let metrics = SessionMetrics(
            sessionID: sessionID,
            outcome: .failed,
            failureCategory: .noSpeechDetected,
            failureStage: .transcribing
        )

        #expect(metrics.outcome == .failed)
        #expect(metrics.failureCategory == .noSpeechDetected)
        #expect(metrics.failureStage == .transcribing)
    }

    @Test("An audio clip reports its duration from frames and rate")
    func clipMetadataReportsDuration() {
        #expect(AudioClipMetadata(sampleRate: 16_000, frameCount: 16_000).duration == .seconds(1))
        #expect(AudioClipMetadata(sampleRate: 16_000, frameCount: 8_000).duration == .milliseconds(500))
        // A degenerate clip reports zero rather than dividing by zero.
        #expect(AudioClipMetadata(sampleRate: 0, frameCount: 100).duration == .zero)
    }

    @Test("An audio segment clamps an inverted range to empty")
    func segmentClampsInvertedRange() {
        let segment = AudioSegment(startFrame: 500, endFrame: 100)
        #expect(segment.frameCount == 0)
        #expect(segment.isEmpty)

        let normal = AudioSegment(startFrame: 100, endFrame: 500)
        #expect(normal.frameCount == 400)
        #expect(!normal.isEmpty)
    }
}
