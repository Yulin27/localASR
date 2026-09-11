import Foundation

/// The language the user expects to dictate in, or a request to let recognition decide.
///
/// A prior, not a constraint: it tells the recogniser what to expect and never narrows what
/// the recogniser may produce. It is one value rather than a set because no runtime in scope
/// accepts a set of languages, and recognition is the only stage that receives it (ADR 0004).
///
/// There is deliberately no case for mixed speech. Code-switching needs no session flag:
/// deterministic processing derives script from the text itself, per run of characters.
public enum LanguageHint: String, Sendable, Equatable, Codable, CaseIterable {
    /// Let the recognition stage decide.
    case automatic
    case chinese
    case english
    case french
}

/// A written-form target for the refinement stage.
///
/// The four built-in modes exist because the degree of written form a destination wants
/// differs: a chat message and an email are not the same transformation.
public enum RefinementMode: String, Sendable, Equatable, Codable, CaseIterable {
    /// 随手记 — light cleanup, minimal restructuring.
    case note
    /// 消息 — chat-shaped: short, no formal greeting or sign-off.
    case message
    /// 邮件 — email-shaped: formal register, greeting and sign-off.
    case email
    /// 结构化 — explicit numbered or bulleted structure.
    case structured
}

/// The user-controlled settings the coordinator freezes at session start.
///
/// Supplied through `DictationSettingsProviding`. `DictationCore` never reads preferences
/// directly, and every value here is copied into the immutable session context so a change
/// made mid-session cannot alter a session already in flight.
///
/// The mode and the refinement toggle are deliberately separate. The mode describes the
/// written form the destination wants and is needed by deterministic processing even when
/// the model stage is switched off, so it cannot be folded into the toggle.
public struct DictationSettings: Sendable, Equatable, Codable {
    public let languageHint: LanguageHint

    /// Used when per-application mode resolution has no rule for the destination.
    public let defaultMode: RefinementMode

    /// Whether the local refiner runs at all. With it off, the deterministic text becomes
    /// the final text, which is the same path a refinement failure takes.
    public let refinementEnabled: Bool

    public init(
        languageHint: LanguageHint,
        defaultMode: RefinementMode,
        refinementEnabled: Bool
    ) {
        self.languageHint = languageHint
        self.defaultMode = defaultMode
        self.refinementEnabled = refinementEnabled
    }

    /// Automatic language, note mode, refinement on.
    public static let standard = DictationSettings(
        languageHint: .automatic,
        defaultMode: .note,
        refinementEnabled: true
    )
}
