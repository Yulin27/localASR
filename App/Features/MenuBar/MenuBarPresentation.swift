import DictationCore

/// What the menu-bar extra shows for one state.
///
/// A pure value, so every state can be tested without SwiftUI. It shows the phase, the failure
/// category, and the fallback outcome, and never transcript text. Its commands are taken from the
/// snapshot's accepted actions rather than derived from the phase (ADR 0005).
struct MenuBarPresentation: Equatable {
    struct Command: Equatable, Identifiable {
        let action: DictationAction
        let title: String
        let accessibilityLabel: String
        let isEnabled: Bool

        var id: DictationAction { action }
    }

    let statusText: String
    /// Secondary lines: fallback outcomes and recovery hints.
    let details: [String]
    let symbolName: String
    let accessibilityLabel: String
    let commands: [Command]

    init(snapshot: SessionSnapshot) {
        let status = Self.status(for: snapshot)
        statusText = status.text
        symbolName = status.symbol
        details = Self.details(for: snapshot)
        accessibilityLabel = "LocalASR, \(status.text)"
        commands = Self.commands(for: snapshot.acceptedActions)
    }

    init(issue: StartupIssue) {
        switch issue {
        case .adaptersUnavailable:
            statusText = "Dictation Unavailable"
            details = ["This build does not include speech recognition yet."]
        }
        symbolName = "exclamationmark.circle"
        accessibilityLabel = "LocalASR, \(statusText)"
        commands = []
    }

    // MARK: - Status

    private static func status(for snapshot: SessionSnapshot) -> (text: String, symbol: String) {
        switch snapshot.phase {
        case .idle: ("Ready", "waveform")
        case .preparing: ("Preparing to Record…", "mic")
        case .recording: ("Recording", "record.circle")
        case .transcribing: ("Transcribing…", "ellipsis.circle")
        case .normalizing: ("Cleaning Up Text…", "ellipsis.circle")
        case .refining: ("Refining…", "ellipsis.circle")
        case .inserting: ("Inserting…", "ellipsis.circle")
        case .completed: completedStatus(snapshot.insertion)
        case .cancelled: ("Cancelled", "xmark.circle")
        case .failed: (failureTitle(snapshot.failure?.category), "exclamationmark.triangle")
        }
    }

    private static func completedStatus(_ insertion: InsertionOutcome?) -> (text: String, symbol: String) {
        switch insertion?.delivery {
        case .insertedDirectly: ("Inserted", "checkmark.circle")
        case .pasteRequested: ("Pasted", "checkmark.circle")
        case .copiedOnly: ("Copied to Clipboard", "doc.on.clipboard")
        case .failed: ("Could Not Insert", "exclamationmark.triangle")
        case nil: ("Done", "checkmark.circle")
        }
    }

    static func failureTitle(_ category: FailureCategory?) -> String {
        switch category {
        case .cancelled: "Cancelled"
        case .permissionDenied: "Permission Required"
        case .deviceUnavailable: "Microphone Unavailable"
        case .noSpeechDetected: "No Speech Detected"
        case .emptyTranscript: "Nothing Recognized"
        case .modelUnavailable: "Model Not Ready"
        case .runtimeFailure: "Processing Failed"
        case .timeout: "Timed Out"
        case .invalidTarget: "No Place to Insert Text"
        case .invalidTransition: "Internal Error"
        case .unsupported: "Not Supported"
        case .unknown, nil: "Something Went Wrong"
        }
    }

    // MARK: - Details

    private static func details(for snapshot: SessionSnapshot) -> [String] {
        var lines: [String] = []
        for fallback in snapshot.fallbacks {
            let line = fallbackDescription(fallback)
            if !lines.contains(line) {
                lines.append(line)
            }
        }
        if snapshot.phase == .failed, snapshot.failure?.recoverability == .recoverable {
            lines.append("Try dictating again.")
        }
        return lines
    }

    static func fallbackDescription(_ fallback: FallbackReason) -> String {
        switch fallback {
        case .voiceActivityUnavailable:
            "Silence trimming was unavailable."
        case .deterministicProcessingUnavailable:
            "Text cleanup was unavailable; kept the recognized text."
        case .refinementTimedOut:
            "Refinement timed out; kept the cleaned-up text."
        case .refinementUnavailable, .refinementEmptyOutput, .refinementLengthOutOfRange,
            .refinementLanguageDamage, .refinementContaminated, .refinementPreamble:
            "Refinement was not used; kept the cleaned-up text."
        case .historyUnavailable:
            "This dictation was not saved to history."
        }
    }

    // MARK: - Commands

    private static func commands(for accepted: AcceptedActions) -> [Command] {
        let toggle: Command =
            switch accepted.toggle {
            case .start:
                Command(
                    action: .toggleRecording,
                    title: "Start Dictation",
                    accessibilityLabel: "Start dictation",
                    isEnabled: true
                )
            case .stop:
                Command(
                    action: .toggleRecording,
                    title: "Stop Dictation",
                    accessibilityLabel: "Stop dictation",
                    isEnabled: true
                )
            case .ignored:
                // Recording has already stopped; there is nothing to start until processing ends.
                Command(
                    action: .toggleRecording,
                    title: "Start Dictation",
                    accessibilityLabel: "Start dictation, unavailable while processing",
                    isEnabled: false
                )
            }

        return [
            toggle,
            Command(
                action: .cancel,
                title: "Cancel",
                accessibilityLabel: "Cancel dictation",
                isEnabled: accepted.cancel
            ),
            Command(
                action: .dismiss,
                title: "Dismiss",
                accessibilityLabel: "Dismiss result",
                isEnabled: accepted.dismiss
            ),
        ]
    }
}
