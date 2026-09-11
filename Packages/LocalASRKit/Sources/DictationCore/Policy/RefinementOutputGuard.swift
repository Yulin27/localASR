import Foundation

/// Per-mode limits on how far a refinement may move from its input.
///
/// The ratios are per mode because the modes are not the same transformation: structured mode
/// is expected to expand a transcript into numbered points, while message mode is expected to
/// be roughly the same length. A single 0.5–1.5 rule would reject legitimate structure.
public struct RefinementGuardPolicy: Sendable, Equatable {
    public struct Limits: Sendable, Equatable {
        /// The smallest acceptable output/input character ratio.
        public let minimumRatio: Double
        /// The largest acceptable output/input character ratio.
        public let maximumRatio: Double

        public init(minimumRatio: Double, maximumRatio: Double) {
            self.minimumRatio = minimumRatio
            self.maximumRatio = maximumRatio
        }
    }

    private let perMode: [RefinementMode: Limits]

    public init(perMode: [RefinementMode: Limits]) {
        self.perMode = perMode
    }

    /// The limits for a mode. Falls back to note's limits for a mode with no entry, so an
    /// unlisted mode can never become a free pass.
    public func limits(for mode: RefinementMode) -> Limits {
        perMode[mode] ?? Self.noteLimits
    }

    static let noteLimits = Limits(minimumRatio: 0.3, maximumRatio: 3.0)

    /// v0.1 limits. Deliberately wide: the guard exists to catch a runaway or empty output,
    /// not to second-guess a rewrite. Anything tighter belongs in a measured ADR.
    public static let v0_1 = RefinementGuardPolicy(perMode: [
        .note: Limits(minimumRatio: 0.3, maximumRatio: 3.0),
        .message: Limits(minimumRatio: 0.3, maximumRatio: 3.0),
        .email: Limits(minimumRatio: 0.4, maximumRatio: 3.5),
        // Structure is the point of this mode, so expansion is expected.
        .structured: Limits(minimumRatio: 0.5, maximumRatio: 6.0),
    ])
}

/// The guard's decision on one refinement output.
public enum RefinementGuardVerdict: Sendable, Equatable {
    /// Accept this text. It may be trimmed of surrounding whitespace.
    case accepted(String)
    /// Discard the refinement and keep the deterministic text.
    case rejected(FallbackReason)
}

/// Decides whether a refiner's output may replace the deterministic text.
///
/// This lives in the core, and outside ``TextRefining``, so that a model adapter cannot
/// certify its own output and no assembly can quietly install a weaker rule set. Only
/// ``RefinementGuardPolicy`` is injectable, because the thresholds are mode data that later
/// phases tune; the checks themselves are not.
public struct RefinementOutputGuard: Sendable {
    private let policy: RefinementGuardPolicy

    public init(policy: RefinementGuardPolicy = .v0_1) {
        self.policy = policy
    }

    public func evaluate(
        _ output: RefinementOutput,
        for request: RefinementRequest
    ) -> RefinementGuardVerdict {
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            return .rejected(.refinementEmptyOutput)
        }

        let input = request.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Shape checks before the length check. A leaked reasoning trace or an assistant
        // preamble is also far longer than its input, so testing length first would report
        // the generic reason and hide the specific, diagnosable one.
        if Self.containsReasoningMarkup(text) {
            return .rejected(.refinementContaminated)
        }

        if Self.hasAssistantPreamble(text) {
            return .rejected(.refinementPreamble)
        }

        let limits = policy.limits(for: request.mode)
        if !input.isEmpty {
            let ratio = Double(text.count) / Double(input.count)
            if ratio < limits.minimumRatio || ratio > limits.maximumRatio {
                return .rejected(.refinementLengthOutOfRange)
            }
        }

        if Self.damagedLanguage(input: input, output: text) {
            return .rejected(.refinementLanguageDamage)
        }

        return .accepted(text)
    }

    // MARK: - Checks

    /// Reasoning markup that a thinking-enabled model leaks into its output.
    ///
    /// A clean adapter strips this before returning, so seeing it here means the adapter did
    /// not, and the output cannot be trusted as final text.
    private static let reasoningMarkers = [
        "<thinking>", "</thinking>", "<think>", "</think>",
        "<reasoning>", "</reasoning>", "<reflection>", "</reflection>",
    ]

    static func containsReasoningMarkup(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return reasoningMarkers.contains { lowered.contains($0) }
    }

    /// Assistant framing that answers the transcript instead of rewriting it.
    ///
    /// Checked only at the start: an email refinement may legitimately contain these words
    /// later in the text, but must not open with them.
    private static let preamblePhrases = [
        "here is", "here's", "sure,", "sure!", "of course", "certainly,",
        "以下是", "下面是", "这是您", "这是你", "已为您", "好的，以下",
        "voici", "voici le", "bien sûr",
    ]

    static func hasAssistantPreamble(_ text: String) -> Bool {
        let head = text.prefix(40).lowercased()
        return preamblePhrases.contains { head.hasPrefix($0) }
    }

    /// Whether the output lost the script the input was written in.
    ///
    /// Deliberately conservative. A false positive costs the user the refinement and falls
    /// back to deterministic text, so this fires only on a large loss, not on a modest shift:
    /// an input with at least eight ideographs must retain a third of them.
    static func damagedLanguage(input: String, output: String) -> Bool {
        let inputIdeographs = ideographCount(input)
        if inputIdeographs >= 8 {
            return ideographCount(output) * 3 < inputIdeographs
        }

        let inputLatin = latinLetterCount(input)
        if inputLatin >= 8 {
            return latinLetterCount(output) * 3 < inputLatin
        }

        return false
    }

    static func ideographCount(_ text: String) -> Int {
        text.unicodeScalars.count { scalar in
            (0x3400...0x4DBF).contains(scalar.value)      // extension A
                || (0x4E00...0x9FFF).contains(scalar.value)  // unified ideographs
                || (0xF900...0xFAFF).contains(scalar.value)  // compatibility ideographs
        }
    }

    static func latinLetterCount(_ text: String) -> Int {
        text.unicodeScalars.count { scalar in
            scalar.properties.isAlphabetic
                && (0x0041...0x024F).contains(scalar.value)  // basic latin through latin extended-B
        }
    }
}
