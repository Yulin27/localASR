import Foundation
import Testing

@testable import DictationCore

@Suite("Session context")
struct SessionContextTests {
    private let editor = ActiveApplication(
        processIdentifier: 501,
        bundleIdentifier: "com.example.editor",
        localizedName: "Editor"
    )

    @Test("Capturing a target keeps the application and the destination consistent")
    func capturedTargetKeepsApplicationConsistent() {
        let target = InsertionTarget(application: editor, elementToken: "focused-field")
        let result = TargetCaptureResult.captured(target)

        #expect(result.application == editor)
        #expect(result.insertionTarget == target)
        #expect(result.unavailableReason == nil)
    }

    @Test("An unavailable destination carries the reason and no target")
    func unavailableDestinationCarriesReason() {
        let result = TargetCaptureResult.unavailable(
            .accessibilityPermissionDenied,
            application: editor
        )

        #expect(result.insertionTarget == nil)
        #expect(result.unavailableReason == .accessibilityPermissionDenied)
        // The frontmost application is readable without Accessibility permission, so a
        // failure to resolve the destination does not cost the history its bundle ID.
        #expect(result.application == editor)
    }

    @Test("The context exposes the destination and source application from the capture")
    func contextDerivesFromTargetCapture() {
        let target = InsertionTarget(application: editor, elementToken: "focused-field")
        let context = makeContext(target: .captured(target))

        #expect(context.application == editor)
        #expect(context.insertionTarget == target)
    }

    @Test("The mode survives the refinement toggle")
    func modeSurvivesRefinementToggle() {
        // Deterministic processing is mode-dependent, so switching the model stage off must
        // not erase which written form the destination wanted.
        let refined = makeContext(mode: .email, isRefinementEnabled: true)
        let deterministic = makeContext(mode: .email, isRefinementEnabled: false)

        #expect(refined.mode == .email)
        #expect(deterministic.mode == .email)
        #expect(refined.isRefinementEnabled)
        #expect(!deterministic.isRefinementEnabled)
    }

    @Test("The context holds its own values, so later settings changes cannot reach it")
    func contextIsFrozen() {
        let context = makeContext(languageHint: .english, mode: .note)

        // A changed settings value is a different value. Nothing in the context above is
        // derived from a live source at read time, so it cannot drift with the preferences.
        let changed = DictationSettings(
            languageHint: .french,
            defaultMode: .email,
            refinementEnabled: false
        )
        #expect(context.languageHint == .english)
        #expect(context.mode == .note)
        #expect(changed.languageHint == .french)
        #expect(context != makeContext(languageHint: changed.languageHint))
    }

    private func makeContext(
        target: TargetCaptureResult? = nil,
        languageHint: LanguageHint = .automatic,
        mode: RefinementMode = .note,
        isRefinementEnabled: Bool = true
    ) -> SessionContext {
        SessionContext(
            id: SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            target: target ?? .captured(InsertionTarget(application: editor)),
            languageHint: languageHint,
            mode: mode,
            isRefinementEnabled: isRefinementEnabled
        )
    }
}
