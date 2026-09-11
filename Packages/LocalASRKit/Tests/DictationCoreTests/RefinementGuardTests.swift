import Testing

@testable import DictationCore

@Suite("Refinement output guard")
struct RefinementGuardTests {
    private let guardRail = RefinementOutputGuard()
    private let engine = EngineIdentifier(name: "refiner")

    @Test("A faithful rewrite is accepted, trimmed of surrounding whitespace")
    func acceptedRewriteIsTrimmed() {
        let input = "我们把发布推迟到下周一，因为测试还没跑完。"
        let verdict = evaluate("\n  我们把发布推迟到下周一，因为测试还没跑完。  \n", input: input)

        #expect(verdict == .accepted(input))
    }

    @Test("A legitimate Chinese opening is not mistaken for preamble")
    func legitimateOpeningIsNotPreamble() {
        let input = "你好，我想确认一下下周的会议时间"
        #expect(evaluate(input + "。", input: input, mode: .email) == .accepted(input + "。"))
    }

    @Test("Empty and whitespace-only output is rejected")
    func emptyOutputIsRejected() {
        #expect(evaluate("", input: "你好呀") == .rejected(.refinementEmptyOutput))
        #expect(evaluate("   \n ", input: "你好呀") == .rejected(.refinementEmptyOutput))
    }

    @Test("Output far longer than the input is rejected")
    func runawayExpansionIsRejected() {
        let input = "把这个发出去"
        #expect(
            evaluate(String(repeating: input, count: 40), input: input)
                == .rejected(.refinementLengthOutOfRange)
        )
    }

    @Test("Output far shorter than the input is rejected")
    func collapsedOutputIsRejected() {
        let input = "我记得上周我们讨论过这个方案的取舍，最后决定先把风险最大的那一块单独拆出来验证。"
        #expect(evaluate("好的", input: input) == .rejected(.refinementLengthOutOfRange))
    }

    @Test("Structured mode permits expansion that note mode would reject")
    func structuredModePermitsExpansion() {
        let input = "先确认范围，再排期，最后补测试"
        let output = """
            1. 先确认这次改动的范围，包括受影响的模块与接口。
            2. 根据确认后的范围安排排期，并预留必要的联调时间。
            3. 补充对应的测试用例，覆盖关键的边界情况。
            """
        let ratio = Double(output.count) / Double(input.count)
        // The point of this case is that the ratio sits between the two modes' ceilings.
        #expect(ratio > 3.0 && ratio < 6.0, "ratio was \(ratio), which does not exercise the gap")

        #expect(evaluate(output, input: input, mode: .structured) == .accepted(output))
        #expect(evaluate(output, input: input, mode: .note) == .rejected(.refinementLengthOutOfRange))
    }

    @Test("Leaked reasoning markup is rejected as contamination")
    func reasoningMarkupIsRejected() {
        let input = "帮我把这个发出去，记得抄送给他"
        #expect(
            evaluate("<thinking>用户想发消息</thinking>把消息发出去。", input: input, mode: .message)
                == .rejected(.refinementContaminated)
        )
    }

    @Test("Assistant preamble is rejected")
    func assistantPreambleIsRejected() {
        let body = "把消息发出去，记得告诉他我们下周再确认细节。"
        #expect(
            evaluate("Here is the cleaned version: " + body, input: body, mode: .message)
                == .rejected(.refinementPreamble)
        )
        #expect(
            evaluate("以下是清理后的文本：" + body, input: body, mode: .message)
                == .rejected(.refinementPreamble)
        )
    }

    @Test("Losing the input's script is rejected")
    func lostScriptIsRejected() {
        let input = "我们下周把这件事定下来，然后开始排期和分工。"
        #expect(
            evaluate("We will decide this next week, then plan the schedule.", input: input)
                == .rejected(.refinementLanguageDamage)
        )
    }

    @Test("A short input is exempt from the script-damage check")
    func shortInputIsExemptFromScriptCheck() {
        // Fewer than eight ideographs is too little signal to conclude damage.
        #expect(evaluate("Send it.", input: "发出去") == .accepted("Send it."))
    }

    @Test("A mode with no configured limits falls back to the strictest defaults")
    func unlistedModeUsesStrictDefaults() {
        let policy = RefinementGuardPolicy(perMode: [:])
        #expect(policy.limits(for: .structured) == RefinementGuardPolicy.noteLimits)

        // An empty table must not turn the guard into a free pass.
        let input = "把这个发出去"
        let verdict = RefinementOutputGuard(policy: policy).evaluate(
            RefinementOutput(text: String(repeating: input, count: 40), engine: engine),
            for: RefinementRequest(
                sessionID: SessionID(),
                text: input,
                mode: .structured
            )
        )
        #expect(verdict == .rejected(.refinementLengthOutOfRange))
    }

    @Test(
        "A dictation that opens like a preamble is not rejected as one",
        arguments: [
            ("sure let's meet at five tomorrow", "Sure, let's meet at five tomorrow."),
            ("of course I can send it tonight", "Of course, I can send it tonight."),
            ("certainly it works for me", "Certainly, it works for me."),
            ("voici le document que tu m'as demandé hier", "Voici le document que tu m'as demandé hier."),
            ("bien sûr je peux venir demain", "Bien sûr, je peux venir demain."),
            ("这是你要的资料请查收", "这是你要的资料，请查收。"),
            ("下面是我们下周的安排先确认范围再排期", "下面是我们下周的安排：先确认范围，再排期。"),
        ]
    )
    func dictatedOpenerIsNotPreamble(input: String, output: String) {
        // The speaker said these words. Punctuating them is the refinement, not a preamble.
        #expect(evaluate(output, input: input, mode: .message) == .accepted(output))
    }

    @Test("A preamble written with a typographic apostrophe is still rejected")
    func typographicApostrophePreambleIsRejected() {
        let body = "把消息发出去，记得告诉他我们下周再确认细节。"
        #expect(
            evaluate("Here’s the cleaned version: " + body, input: body, mode: .message)
                == .rejected(.refinementPreamble)
        )
    }

    @Test(
        "Email mode may frame a short dictation with a greeting and sign-off",
        arguments: [
            ("明天请假", "您好，\n\n我明天需要请假一天。\n\n谢谢！"),
            ("running late", "Hi,\n\nI'm running about ten minutes late.\n\nThanks!"),
        ]
    )
    func shortDictationMayGainEmailFraming(input: String, output: String) {
        // A fixed greeting and sign-off dwarf a short input, so a pure ratio cannot tell this
        // apart from a runaway output.
        #expect(evaluate(output, input: input, mode: .email) == .accepted(output))
    }

    @Test("Translating away the Latin terms of a mixed dictation is rejected")
    func lostLatinInMixedDictationIsRejected() {
        let input = "我们用 Kubernetes 和 PostgreSQL 部署这个服务吧"
        #expect(
            evaluate("我们用容器编排平台和数据库部署这个服务吧。", input: input)
                == .rejected(.refinementLanguageDamage)
        )

        // Keeping the terms is faithful, with or without mixed-script spacing.
        let spaced = "我们用 Kubernetes 和 PostgreSQL 部署这个服务吧。"
        let unspaced = "我们用Kubernetes和PostgreSQL部署这个服务吧。"
        #expect(evaluate(spaced, input: input) == .accepted(spaced))
        #expect(evaluate(unspaced, input: input) == .accepted(unspaced))
    }

    @Test("Output for an input with no text is never accepted")
    func outputForEmptyInputIsNotAccepted() {
        let hallucination = "Thank you for watching."
        #expect(evaluate(hallucination, input: "") != .accepted(hallucination))
        #expect(evaluate(hallucination, input: " \n") != .accepted(hallucination))
    }

    private func evaluate(
        _ output: String,
        input: String,
        mode: RefinementMode = .note
    ) -> RefinementGuardVerdict {
        guardRail.evaluate(
            RefinementOutput(text: output, engine: engine),
            for: RefinementRequest(sessionID: SessionID(), text: input, mode: mode)
        )
    }
}
