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
                mode: .structured,
                language: .chinese
            )
        )
        #expect(verdict == .rejected(.refinementLengthOutOfRange))
    }

    private func evaluate(
        _ output: String,
        input: String,
        mode: RefinementMode = .note
    ) -> RefinementGuardVerdict {
        guardRail.evaluate(
            RefinementOutput(text: output, engine: engine),
            for: RefinementRequest(
                sessionID: SessionID(),
                text: input,
                mode: mode,
                language: .automatic
            )
        )
    }
}
