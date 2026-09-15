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

        /// Characters a mode may add on top of the ratio, whatever the input length.
        ///
        /// Some framing does not scale with the dictation: an email's greeting and sign-off
        /// are the same length whether the user dictated four characters or four hundred, so
        /// a pure ratio rejects every short dictation in those modes. The ceiling is
        /// therefore `max(maximumRatio × input, input + fixedAllowance)`, which still catches
        /// a runaway output because that grows with the input it ran away from.
        public let fixedAllowance: Int

        public init(minimumRatio: Double, maximumRatio: Double, fixedAllowance: Int = 48) {
            self.minimumRatio = minimumRatio
            self.maximumRatio = maximumRatio
            self.fixedAllowance = fixedAllowance
        }

        /// The largest output this mode accepts for an input of `inputLength` characters.
        func ceiling(forInputOf inputLength: Int) -> Double {
            max(Double(inputLength) * maximumRatio, Double(inputLength + fixedAllowance))
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
    ///
    /// The 48-character allowance is the room a greeting line and a sign-off need — "Hi,"
    /// through "Best regards," and a name — which is what a short dictation gains in email
    /// mode without gaining a single new fact. It is far below any runaway: an output 48
    /// characters longer than its input is a sentence, not a model that started writing.
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

        if Self.hasAssistantPreamble(text, input: input) {
            return .rejected(.refinementPreamble)
        }

        if input.isEmpty {
            // Nothing was dictated, so whatever came back is invention rather than a rewrite —
            // a model handed an empty transcript tends to produce a plausible sentence of its
            // own. The coordinator fails an empty transcript before refinement; this is the
            // second line of defence, and there is no ratio that could express it.
            return .rejected(.refinementLengthOutOfRange)
        }

        let limits = policy.limits(for: request.mode)
        let length = Double(text.count)
        if length < Double(input.count) * limits.minimumRatio
            || length > limits.ceiling(forInputOf: input.count)
        {
            return .rejected(.refinementLengthOutOfRange)
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
    /// Openers that are framing only when the speaker did not use them.
    ///
    /// Every one of these is also a perfectly ordinary way to start a dictated message, so
    /// the input has the final say.
    private static let preamblePhrases = [
        "here is", "here's", "sure,", "sure!", "of course", "certainly,",
        "以下是", "下面是", "这是您", "这是你", "已为您", "好的，以下",
        "voici", "voici le", "bien sûr",
    ]

    /// The three parts of framing that names the transcript, in order and adjacent: an
    /// introduction, a word for what was done to the text, and a word for the text itself.
    ///
    /// All three together is a sentence a model writes *about* someone's words. Any two of
    /// them is ordinary dictation, which is why the artifact is required: "here is the
    /// revised schedule" is a person talking about their own work, and "以下是修改后的计划"
    /// is that same sentence in Chinese.
    ///
    /// Latin entries carry their trailing space, because a normalized opening separates
    /// words with one; Chinese is written without.
    private static let framingIntroductions = [
        "here is ", "here's ", "this is ", "以下是", "下面是", "这是",
    ]

    /// The determiner between the introduction and the edit, where the language has one.
    ///
    /// Framing is as readily "here is a revised version" or "here is your corrected text" as
    /// it is "the"; the empty string covers Chinese, and English without one.
    private static let framingDeterminers = ["the ", "a ", "an ", "your ", "my ", ""]
    private static let framingEdits = [
        "cleaned up ", "cleaned ", "corrected ", "revised ", "polished ", "rewritten ",
        "edited ", "tidied ", "清理后的", "整理后的", "修改后的", "润色后的", "优化后的",
    ]
    private static let framingArtifacts = [
        "version", "text", "transcript", "wording", "文本", "版本", "转写", "文字",
    ]

    /// French puts the adjective after the noun, so its framing is listed rather than
    /// composed from the three parts above.
    private static let frenchFraming = [
        "voici le texte corrigé", "voici le texte nettoyé", "voici le texte révisé",
        "voici la version corrigée", "voici la version nettoyée",
    ]

    private static let normalizedPreamblePhrases = preamblePhrases.map(normalizedOpening)
    private static let normalizedFrenchFraming = frenchFraming.map(normalizedOpening)

    /// Whether the output opens with assistant framing the speaker did not dictate.
    ///
    /// The phrase alone is not evidence. People open dictated messages with "sure", "voici"
    /// and "这是你" all the time, and punctuating such an opening is the refinement working,
    /// not a preamble — so an opener counts only when the input did not already start with
    /// it. Framing that names the transcript counts either way, which is what stops the
    /// canonical preamble from walking through on a first word the speaker happened to use:
    /// "here is my plan" does not license "Here is the cleaned version: …".
    ///
    /// Every matching opener is considered, not the first. They overlap, and stopping at the
    /// shortest match would clear the output on the strength of a word the speaker did say:
    /// "voici mon problème" refined to "Voici le texte corrigé : …" shares "voici" with its
    /// input, while the framing that was added is "voici le".
    static func hasAssistantPreamble(_ text: String, input: String) -> Bool {
        let head = normalizedOpening(text)
        if namesTheTranscript(head) {
            return true
        }
        let inputHead = normalizedOpening(input)
        for phrase in normalizedPreamblePhrases where opensWith(head, phrase) {
            guard opensWith(inputHead, phrase) else { return true }

            // The speaker did open this way, but framing tucked in behind their own opener
            // is still framing: "sure send it" does not license "Sure, here is the corrected
            // text: send it".
            let afterPhrase = head.dropFirst(phrase.count).drop { $0 == " " }
            if namesTheTranscript(String(afterPhrase)) {
                return true
            }
        }
        return false
    }

    /// Whether a normalized opening introduces the transcript by name.
    static func namesTheTranscript(_ head: String) -> Bool {
        if normalizedFrenchFraming.contains(where: { head.hasPrefix($0) }) {
            return true
        }
        for introduction in framingIntroductions where head.hasPrefix(introduction) {
            let afterIntroduction = head.dropFirst(introduction.count)
            for determiner in framingDeterminers where afterIntroduction.hasPrefix(determiner) {
                let afterDeterminer = afterIntroduction.dropFirst(determiner.count)
                for edit in framingEdits where afterDeterminer.hasPrefix(edit) {
                    // On a word boundary, or "the revised textbook chapter" would read as
                    // framing because "textbook" begins with "text".
                    let afterEdit = String(afterDeterminer.dropFirst(edit.count))
                    if framingArtifacts.contains(where: { opensWith(afterEdit, $0) }) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// The opening of `text`, lowercased, with typographic apostrophes straightened and
    /// punctuation reduced to single spaces.
    ///
    /// Comparing normalized openings is what lets "sure let's meet" match the refinement
    /// "Sure, let's meet.", and what keeps a preamble written "Here’s" from slipping past the
    /// straight-apostrophe spelling.
    static func normalizedOpening(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for scalar in text.prefix(60).replacingOccurrences(of: "\u{2019}", with: "'").unicodeScalars {
            let separates =
                CharacterSet.whitespacesAndNewlines.contains(scalar)
                || (CharacterSet.punctuationCharacters.contains(scalar) && scalar != "'")
            if separates {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.unicodeScalars.append(" ")
                pendingSpace = false
            }
            result.unicodeScalars.append(scalar)
        }
        return result.lowercased()
    }

    /// Whether a normalized opening starts with `phrase`, on a word boundary where the script
    /// has one. Without the boundary "sure" would also match "surely"; scripts written without
    /// spaces have no boundary to check.
    private static func opensWith(_ head: String, _ phrase: String) -> Bool {
        guard !phrase.isEmpty, head.hasPrefix(phrase) else { return false }
        guard let last = phrase.unicodeScalars.last,
              let next = head.unicodeScalars.dropFirst(phrase.unicodeScalars.count).first
        else { return true }
        return !(isLatinLetter(last) && isLatinLetter(next))
    }

    /// Whether the output lost a script the input was written in.
    ///
    /// Every script the input has enough of is checked, not only the dominant one. Mixed
    /// Han/Latin dictation is the plurality of the corpus (ADR 0004), and a refiner that
    /// translates "我们用 Kubernetes 部署" into pure Chinese keeps every ideograph while
    /// destroying the technical terms — a loss the dominant script alone cannot see.
    ///
    /// Deliberately conservative. A false positive costs the user the refinement and falls
    /// back to deterministic text, so this fires only on a large loss, not on a modest shift:
    /// a script the input used at least eight times must keep a third of it.
    static func damagedLanguage(input: String, output: String) -> Bool {
        lostMostOf(ideographCount, input: input, output: output)
            || lostMostOf(latinLetterCount, input: input, output: output)
    }

    private static func lostMostOf(
        _ count: (String) -> Int,
        input: String,
        output: String
    ) -> Bool {
        let before = count(input)
        guard before >= 8 else { return false }
        return count(output) * 3 < before
    }

    static func ideographCount(_ text: String) -> Int {
        text.unicodeScalars.count { scalar in
            (0x3400...0x4DBF).contains(scalar.value)      // extension A
                || (0x4E00...0x9FFF).contains(scalar.value)  // unified ideographs
                || (0xF900...0xFAFF).contains(scalar.value)  // compatibility ideographs
        }
    }

    static func latinLetterCount(_ text: String) -> Int {
        text.unicodeScalars.count(where: isLatinLetter)
    }

    static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic
            && (0x0041...0x024F).contains(scalar.value)  // basic latin through latin extended-B
    }
}
