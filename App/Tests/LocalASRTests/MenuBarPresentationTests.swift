import DictationCore
import Foundation
import Testing

@testable import LocalASR

@Suite("Menu-bar presentation")
struct MenuBarPresentationTests {
    private static let allFailureCategories: [FailureCategory] = [
        .cancelled, .permissionDenied, .deviceUnavailable, .noSpeechDetected, .emptyTranscript,
        .modelUnavailable, .runtimeFailure, .timeout, .invalidTarget, .invalidTransition,
        .unsupported, .unknown,
    ]

    @Test("Every phase has a status, a symbol, and an accessibility label", arguments: DictationPhase.allCases)
    func everyPhaseIsPresented(_ phase: DictationPhase) {
        let presentation = MenuBarPresentation(snapshot: SessionSnapshot(phase: phase))

        #expect(!presentation.statusText.isEmpty)
        #expect(!presentation.symbolName.isEmpty)
        #expect(presentation.accessibilityLabel.contains(presentation.statusText))
        #expect(presentation.commands.map(\.action) == [.toggleRecording, .cancel, .dismiss])
        #expect(presentation.commands.allSatisfy { !$0.accessibilityLabel.isEmpty })
    }

    @Test("Phases in flight and at rest are told apart")
    func phasesAreDistinguishable() {
        let statuses = DictationPhase.allCases.map {
            MenuBarPresentation(snapshot: SessionSnapshot(phase: $0)).statusText
        }
        #expect(Set(statuses).count == statuses.count)
    }

    @Test("Every failure category has its own title", arguments: allFailureCategories)
    func everyFailureCategoryIsPresented(_ category: FailureCategory) {
        let snapshot = SessionSnapshot(
            phase: .failed,
            failure: DictationFailure(stage: .transcribing, category: category, recoverability: .recoverable)
        )
        let presentation = MenuBarPresentation(snapshot: snapshot)

        #expect(presentation.statusText == MenuBarPresentation.failureTitle(category))
        #expect(presentation.symbolName == "exclamationmark.triangle")
        #expect(presentation.details.contains("Try dictating again."))
    }

    @Test("Failure titles are distinct across categories")
    func failureTitlesAreDistinct() {
        let titles = Self.allFailureCategories.map(MenuBarPresentation.failureTitle)
        #expect(Set(titles).count == titles.count)
    }

    @Test("A non-recoverable failure does not suggest trying again")
    func nonRecoverableFailureOffersNoRetryHint() {
        let snapshot = SessionSnapshot(
            phase: .failed,
            failure: DictationFailure(stage: .preparing, category: .unsupported, recoverability: .nonRecoverable)
        )
        #expect(MenuBarPresentation(snapshot: snapshot).details.isEmpty)
    }

    @Test("A refinement fallback is shown as a detail of a completed session")
    func refinementFallbackIsShown() {
        let snapshot = SessionSnapshot(
            phase: .completed,
            insertion: InsertionOutcome(delivery: .insertedDirectly, verification: .confirmed),
            fallbacks: [.refinementTimedOut, .historyUnavailable]
        )
        let presentation = MenuBarPresentation(snapshot: snapshot)

        #expect(presentation.statusText == "Inserted")
        #expect(presentation.details == [
            "Refinement timed out; kept the cleaned-up text.",
            "This dictation was not saved to history.",
        ])
    }

    @Test("Copied-only delivery says the text is on the clipboard")
    func copiedOnlyIsShown() {
        let snapshot = SessionSnapshot(phase: .completed, insertion: .copiedOnly(.targetUnavailable))
        let presentation = MenuBarPresentation(snapshot: snapshot)

        #expect(presentation.statusText == "Copied to Clipboard")
        #expect(presentation.symbolName == "doc.on.clipboard")
    }

    @Test("Commands come from accepted actions, not from the phase")
    func commandsFollowAcceptedActions() {
        // The cleanup window: the phase still reads inserting, but the coordinator has let the
        // session go (ADR 0005).
        let snapshot = SessionSnapshot(
            phase: .inserting,
            acceptedActions: AcceptedActions(toggle: .start, cancel: false, dismiss: false)
        )
        let commands = MenuBarPresentation(snapshot: snapshot).commands

        #expect(commands[0] == .init(
            action: .toggleRecording,
            title: "Start Dictation",
            accessibilityLabel: "Start dictation",
            isEnabled: true
        ))
        #expect(commands[1].isEnabled == false)
        #expect(commands[2].isEnabled == false)
    }

    @Test("The toggle is titled by what it would do")
    func toggleTitles() {
        func toggle(_ value: AcceptedActions.Toggle) -> MenuBarPresentation.Command {
            let actions = AcceptedActions(toggle: value, cancel: false, dismiss: false)
            return MenuBarPresentation(snapshot: SessionSnapshot(phase: .idle, acceptedActions: actions)).commands[0]
        }

        #expect(toggle(.start).title == "Start Dictation")
        #expect(toggle(.start).isEnabled)
        #expect(toggle(.stop).title == "Stop Dictation")
        #expect(toggle(.stop).isEnabled)
        #expect(toggle(.ignored).isEnabled == false)
    }

    @Test("A snapshot's transcript text never reaches the presentation")
    func transcriptTextIsNeverShown() {
        let secret = "PRIVATE-DICTATION-TEXT"
        let snapshot = SessionSnapshot(
            phase: .completed,
            transcript: Transcript(rawText: secret, normalizedText: secret, finalText: secret),
            insertion: .copiedOnly(.targetUnavailable),
            fallbacks: FallbackReason.allCases
        )
        let presentation = MenuBarPresentation(snapshot: snapshot)
        let shown = [presentation.statusText, presentation.accessibilityLabel]
            + presentation.details
            + presentation.commands.flatMap { [$0.title, $0.accessibilityLabel] }

        #expect(shown.allSatisfy { !$0.contains(secret) })
    }

    @Test("A not-ready application names the issue and offers no dictation commands")
    func notReadyIsPresented() {
        let presentation = MenuBarPresentation(issue: .adaptersUnavailable)

        #expect(presentation.statusText == "Dictation Unavailable")
        #expect(!presentation.details.isEmpty)
        #expect(presentation.commands.isEmpty)
        #expect(presentation.accessibilityLabel.contains("Dictation Unavailable"))
    }
}
