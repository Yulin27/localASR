# ADR 0004: Language is a single prior, and script is derived from text

- Status: Accepted
- Date: 2026-09-11

## Context

Phase 1 froze a `LanguageHint` into `SessionContext` and passed it to both the recognition and the
deterministic stages. ADR 0003 did not cover it. Two questions were left open: whether a session's
language is a single value or a set, and which stage owns the language a language-dependent rule
acts on.

The product motivation for a set is real. Chinese, English, French, and code-switching are all
first-class, and a plausible interaction is "tell the app which languages you speak so it stops
considering the rest." A Phase 0 probe tested whether the pinned runtime can honour that.

Paths below of the form `Scripts/phase0/…` and `Sources/Phase0ASR/…` belong to the standalone
Phase 0 feasibility harness. It is sequenced before this work but lands on its own branch, so those
files are not part of the Phase 1 package.

**What the probe measured.** Qwen3-ASR 0.6B 8-bit MLX (`aufklarer/Qwen3-ASR-0.6B-MLX-8bit`,
revision `0bfa1071…`) through the pinned native runtime (`ca4daaf9…`) on Apple M4, macOS 15.5:
six clips of Chinese, English, and Chinese/English mixed dictation, one corpus pass, one warm
repetition, four hint arms.

| Hint | Completed | Expected language preserved | Identical to auto |
| --- | --- | --- | --- |
| auto (omitted) | 6/6 | 6/6 | baseline |
| `zh` | 6/6 | 6/6 | 5/6 |
| `en` | 6/6 | 6/6 | 4/6 |
| `{zh,en}` | 6/6 | 6/6 | 4/6 |

**What the probe did not measure.** The corpus contained no French — `corpus_complete` is false and
`missing_categories` is `["fr"]` — so all six clips are English, Chinese, or mixed, and the French
path is untested. No arm's figures are an accuracy measurement: agreement with the automatic arm
says the hint perturbed the output, not that either output is right. The harness computes no CER or
WER because the Typeless reference text is itself a cloud refinement result
(`Scripts/phase0/README.md`, "Interpretation"). `detected_language` in the harness is
`NLLanguageRecognizer.dominantLanguage(for:)` over the finished transcript
(`Sources/Phase0ASR/main.swift:243-245`), not metadata from the recogniser; nothing in these results
reports what the model believed it heard.

**What the probe established.** The runtime takes one optional language string and inserts it into
the decoder prompt. `{zh,en}` is accepted without error and becomes literal prompt text
`language {zh,en}`; it is not a validated allowlist. There is no language-set parameter, and no
language-identification stage is reachable through this runtime.

## Decision

### 1. A session's language hint is a single value, and it is a prior, not a constraint

`LanguageHint` stays single-valued. The contract does not model a set of allowed languages, because
no available runtime accepts one, and a type that promises a constraint the wire cannot enforce is
worse than no type. A hint expresses a user's preference about which language they are speaking; it
does not narrow the recogniser's search space.

`.mixed` is removed. It maps to no wire difference from `.automatic`, and code-switching is handled
by decision 3, which does not need a session flag. A user who mixes languages is described by their
settings, not by a per-session value no stage reads.

### 2. An unrecognised hint degrades to automatic; it must never reach the prompt

Every `SpeechRecognizing` adapter validates the hint against the codes it knows. A value it does not
recognise is treated as absent. Passing an unvalidated string into a decoder prompt turns a settings
error into plausible-looking wrong transcripts, with nothing in the metrics to show for it — a
silent failure, which is the one failure mode worth spending a contract rule on.

### 3. The deterministic stage derives script from the text, per token

Language-dependent processing does not consume a session language label. It classifies the text it
is given — Han versus Latin ranges, per run of characters.

Spec §6's v0.1 rules are script-driven: Chinese/Latin spacing, full-width versus half-width
punctuation, ITN normalisation, and filler removal, whose lists are script-disjoint in practice
(`这个/那个/就是` versus `um, uh` versus `euh, ben, du coup`). The derivation is a pure function of
its input, so it is Foundation-only, deterministic, and unit-testable with no model — which is what
`DictationCore` requires. Deriving per token also expresses code-switching, which a single-label
session hint cannot, and which is the plurality of the project's own corpus: 14 of the 33 Typeless
clips are mixed Han/Latin.

### 4. `RecognitionResult.language` is removed

The field's comment claims "the language the recogniser actually used, when it reports one." No
runtime in scope reports one. Keeping it would mean populating it from a text classifier inside the
adapter — an Apple framework's post-hoc guess wearing a domain type that asserts recogniser
provenance. A value with no producer is a contract that lies, so it goes.

With it, `SessionContext.languageHint`'s only consumer is the recognition request.

## Consequences

- The interaction "choose up to three languages" is not implementable at the recognition boundary.
  It can return only with a provider that accepts a language set, which is a provider commitment for
  a later ADR.
- `DictationSettings.languageHint` survives as a single preference, default `.automatic`. A session
  with no strong single-language preference sets nothing.
- A hint is expected to change output on some inputs. That effect is not a quality claim until
  Phase 4 measures CER/WER against references, and Phase 4 owns the provider commitment.
- The deterministic stage gains tests that are text-in/text-out and need no model, no microphone,
  and no permission — consistent with the package's verification rule.
- Divergence signals built on "the user said Chinese but the text is Latin" are unavailable from the
  recogniser. If wanted, they are derived from the same script classification as decision 3.
- `ARCHITECTURE.md`'s statements about the hint stay accurate — it is captured at session start and
  recorded in history — but it is no longer an input to deterministic processing.
- The Phase 0 corpus still has no French. Nothing here about French is measured, and the gate cannot
  pass until it is.

## Alternatives considered

- **Model the hint as a set** (`LanguageConstraint.only(Set<SpokenLanguage>)`): would express the
  product idea directly in the domain, but against this runtime it degrades to literal prompt text,
  so the type would promise a narrowing that does not happen.
- **Keep `RecognitionResult.language`, populated by the adapter**: preserves a place for the value
  should a future runtime report it, at the cost of a domain field whose comment would be false for
  every adapter that exists. Adding it later is additive; keeping a fiction is not.
- **Keep a session-level language as the input to deterministic rules**: cannot express
  code-switching, and depends on a label whose only source would be a text classifier.
- **Reject an unrecognised hint by throwing**: consistent with typed failures elsewhere, but it
  turns a settings typo into a lost dictation. Degrading to automatic keeps the user's words.
- **Keep `.mixed` as a distinct user intent**: honest about the product requirement, but nothing
  reads it once decision 3 lands, and the UI would offer a choice that changes nothing.
