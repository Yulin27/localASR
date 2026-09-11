import Foundation
import Testing

@testable import DictationCore

@Suite("Session snapshot")
struct SnapshotTests {
    @Test("The idle snapshot names no session")
    func idleSnapshotNamesNoSession() {
        #expect(SessionSnapshot.idle.phase == .idle)
        #expect(SessionSnapshot.idle.sessionID == nil)
        #expect(SessionSnapshot.idle.context == nil)
        #expect(SessionSnapshot.idle.transcript == .empty)
        #expect(SessionSnapshot.idle.fallbacks.isEmpty)
    }

    @Test("A session is named before its context has been captured")
    func sessionIsNamedBeforeContextExists() {
        let id = SessionID()
        let snapshot = SessionSnapshot(phase: .preparing, sessionID: id)

        #expect(snapshot.sessionID == id)
        #expect(snapshot.context == nil)
    }

    @Test("A snapshot carries clip metadata without carrying the clip")
    func snapshotCarriesMetadataOnly() {
        let metadata = AudioClipMetadata(sampleRate: 16_000, frameCount: 48_000)
        let snapshot = SessionSnapshot(phase: .recording, audio: metadata)

        #expect(snapshot.audio == metadata)
        #expect(snapshot.audio?.duration == .seconds(3))
        #expect(snapshot.audio?.channelCount == 1)
    }

    @Test("Fallbacks accumulate in order without repeating")
    func fallbacksAccumulateInOrder() {
        let snapshot = SessionSnapshot(phase: .refining)
            .appending(fallback: .voiceActivityUnavailable)
            .appending(fallback: .refinementTimedOut)
            .appending(fallback: .voiceActivityUnavailable)

        #expect(snapshot.fallbacks == [.voiceActivityUnavailable, .refinementTimedOut])
    }

    @Test("Appending a fallback leaves the phase and text alone")
    func appendingFallbackPreservesState() {
        let original = SessionSnapshot(
            phase: .inserting,
            transcript: Transcript(rawText: "raw", normalizedText: "normalized")
        )
        let updated = original.appending(fallback: .refinementUnavailable)

        #expect(updated.phase == .inserting)
        #expect(updated.transcript == original.transcript)
    }

    @Test("The best available text prefers the latest stage that produced text")
    func bestAvailableTextPrefersLatestStage() {
        #expect(Transcript.empty.bestAvailableText == nil)
        #expect(Transcript(rawText: "raw").bestAvailableText == "raw")
        #expect(Transcript(rawText: "raw", normalizedText: "norm").bestAvailableText == "norm")
        #expect(
            Transcript(rawText: "raw", normalizedText: "norm", finalText: "final")
                .bestAvailableText == "final"
        )
    }

    @Test("A refinement summary distinguishes policy, rejection, and failure")
    func refinementSummaryDistinguishesOutcomes() {
        #expect(RefinementSummary(outcome: .skippedByPolicy).outcome == .skippedByPolicy)
        #expect(
            RefinementSummary(outcome: .rejected(.refinementLengthOutOfRange)).outcome
                == .rejected(.refinementLengthOutOfRange)
        )
        #expect(
            RefinementSummary(outcome: .unavailable(.refinementTimedOut)).outcome
                == .unavailable(.refinementTimedOut)
        )
    }

    @Test("Insertion outcomes keep delivery, verification, and failure separate")
    func insertionOutcomeKeepsDimensionsSeparate() {
        let outcome = InsertionOutcome.copiedOnly(.accessibilityPermissionDenied)

        #expect(outcome.delivery == .copiedOnly)
        #expect(outcome.verification == .notAttempted)
        #expect(outcome.failure == .accessibilityPermissionDenied)

        // A posted paste is not proof the target accepted the text.
        let unverified = InsertionOutcome(
            delivery: .pasteRequested,
            verification: .unconfirmed
        )
        #expect(unverified.failure == nil)
        #expect(unverified.verification == .unconfirmed)
    }
}
