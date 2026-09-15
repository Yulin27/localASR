# LocalASR v0.1 Implementation Plan

- Status: Active
- Last updated: 2026-09-15
- Product scope: [`Spec.md`](../Spec.md)
- Architecture: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Accepted decisions: [`docs/adr/`](adr/)

## Purpose

This document records the implementation order for v0.1. It sequences work and
defines exit gates; it does not replace the product scope or accepted architecture.

The repository is currently an architecture scaffold. The Swift package builds,
but its targets contain module markers only, there is no Xcode application project,
and no production ML runtime has been selected.

## Ordering rule

Perform a small, standalone model feasibility check before application work, but do
not begin with production model integration. The feasibility check answers whether
the intended models can run credibly on the target Mac. The core workflow and first
vertical slice still use fakes so model SDKs cannot define domain or orchestration
boundaries.

The full provider comparison and commitment happen only after the mock-backed
vertical slice exists.

## Phase 0: Model feasibility gate

### Goal

Determine whether the intended ASR and refinement configurations can run locally on
the primary development Mac before investing in the complete application pipeline.

### Work

- Exercise Qwen3-ASR 0.6B 8-bit through at least one realistic native runtime.
- Exercise Qwen3-4B-Instruct 4-bit through MLX with thinking disabled.
- Use short, real Chinese, English, French, and mixed-language inputs.
- Measure cold load, warm inference, end-to-end inference, idle memory, peak memory,
  and artifact size.
- Test the two runtimes sequentially and while co-resident if the proposed residency
  policy keeps both loaded.
- Repeat enough runs to expose crashes, memory pressure, or obvious thermal
  degradation.
- Record the exact machine and OS, runtime versions, immutable model revisions,
  quantizations, settings, licenses, and measurement units.

This is a feasibility smoke test, not the final quality benchmark. It must not be
used to claim CER, WER, latency percentiles, or written-quality performance without
a representative corpus and repeated measurements.

### Exit gate

- Both stages load and produce locally generated output without a crash.
- The ASR preserves the spoken language on representative inputs.
- The refiner produces output with thinking disabled.
- Memory pressure remains safe on the reference machine.
- Measurements show a credible path toward the latency and memory targets in the
  spec.

If the gate fails, evaluate another runtime, quantization, or measured residency
policy before changing product scope. A change to the committed model/runtime or
distribution policy requires license review and usually an ADR.

## Phase 1: Core contracts and coordinator

Implement the stable center in `DictationCore`:

- Session ID, immutable session context, language hint, refinement mode, transcript
  stages, phase snapshots, typed failures, and structured insertion outcomes.
- Narrow v0.1 ports for capture, VAD, recognition, deterministic processing,
  refinement, insertion, target capture, mode resolution, history, and metrics.
- The `DictationCoordinator` actor as the only owner of phase advancement.
- Deterministic fakes and coordinator tests covering toggle start/stop, every phase,
  cancellation at each await boundary, stale results, duplicate actions, cleanup,
  and fallback behavior.

### Exit gate

The complete batch workflow is executable in tests using fakes, and all package
builds and tests pass without microphone, Accessibility, network, or model access.

## Phase 2: Menu-bar application shell

- Create the macOS 15 SwiftUI/AppKit application project with local signing.
- Add `MenuBarExtra`, `LSUIElement`, a minimal non-focus-stealing status UI, and a
  `@MainActor` application model.
- Create production, preview, and test assemblies in `App/Composition`.
- Render coordinator snapshots and forward semantic user actions without moving
  workflow policy into views.

Step-by-step plan: [`plans/phase-2.md`](plans/phase-2.md).

Status: complete (2026-09-15). The manual exit-gate checklist passed on the Debug and
Release builds; the results are recorded in the plan.

### Exit gate

The application launches as a menu-bar app and can drive the fake coordinator from
the menu without constructing dependencies inside feature views.

## Phase 3: Microphone-to-mock-transcript-to-copy slice

- Implement toggle shortcut activation and duplicate/auto-repeat filtering.
- Capture the active application and insertion destination on the first activation.
- Record bounded 16 kHz mono audio and stop only on the second activation.
- Return a mock transcript through `SpeechRecognizing`.
- Use identity deterministic/refinement adapters.
- Deliver through an initial copy-only inserter.
- Show recording, processing, completion, and recoverable failure states.
- Record privacy-safe phase timing from the first executable slice.
- Make quitting wait, with a bound, for an in-flight session's cleanup (device release, clip
  disposal, history write). Phase 2's shutdown cancels the session without awaiting it.

### Exit gate

A user can press once, record, press again, receive a mock transcript, and copy it
without focus changes corrupting the frozen destination or stale callbacks changing
the active session.

## Phase 4: ASR benchmark and selection

- Build a reproducible, opt-in benchmark using real Chinese, English, French,
  code-switching, technical-term, silence, and long-dictation audio.
- Compare viable Qwen3-ASR runtimes and quantizations behind the same batch contract.
- Measure CER/WER, cold and warm latency, peak memory, model preparation time,
  artifact size, cancellation, and long-input ordering.
- Verify code, model-weight, conversion, and transitive licenses.
- Record the selected provider, immutable revisions, quantization, and tradeoffs in
  an ADR before making it the default.

### Exit gate

One provider has measured evidence supporting its selection and a license compatible
with the closed-source, directly distributed product.

## Phase 5: Production ASR and model preparation

- Implement the selected `SpeechRecognizing` adapter and its contract tests.
- Add a pinned model manifest, checksums, expected contents, compatibility metadata,
  and license records.
- Implement staged download, verification, atomic promotion, preparation, readiness,
  cancellation, and corrupt-cache recovery.
- Keep model download and preparation outside the recording path.
- Connect real ASR to the vertical slice without exposing provider types outside
  `SpeechEngines`.

### Exit gate

Prepared models produce one session-scoped final raw transcript through the core
port, including cancellation and typed failure behavior.

## Phase 6: Deterministic written-text processing

- Preserve `rawText`, `normalizedText`, and `finalText` as distinct values.
- Add small, ordered, versioned transforms for Unicode cleanup, ASR artifacts,
  punctuation, mixed-script spacing, filler words, ITN, dangling particles, and
  conservative self-correction.
- Maintain curated Chinese, English, French, and mixed-script fixtures.
- Evaluate native Swift ITN versus a permissively licensed FST bridge separately;
  do not hide that decision inside unrelated regex work.

### Exit gate

Every required v0.1 deterministic rule has focused multilingual tests, and failure
cannot overwrite or discard valid raw text.

## Phase 7: Reliable text insertion

- Implement Accessibility selected-text replacement.
- Add the clipboard-plus-paste fallback with complete item/type snapshotting and
  session ownership-safe restoration.
- Retain copy-only fallback with a visible outcome.
- Handle invalid targets, missing permission, Secure Input, password fields, and
  unresponsive applications without losing final text.
- Begin the manual compatibility matrix defined by the spec.

### Exit gate

All three delivery outcomes are covered by adapter tests, and representative apps
have recorded manual results rather than assumed support.

## Phase 8: Local refinement

- Implement isolated per-transcript inference, deadline, cancellation, output-token
  limit, thinking/preamble cleanup, and structured fallback reasons.
- Implement mode-specific output guards before enabling the real model adapter.
- Connect the measured local Qwen3-4B-Instruct runtime with thinking disabled.
- Re-measure latency and memory with ASR and refinement in the real application.
- Fall back to `normalizedText` for timeout, runtime failure, empty output, excessive
  expansion, script/language damage, or contaminated output.

### Exit gate

The refiner improves curated examples without answering transcript content, and
every invalid/error path preserves deterministic text.

## Phase 9: Modes and per-application behavior

- Implement the four built-in modes: note, message, email, and structured.
- Resolve the mode from the source bundle ID captured at recording start.
- Keep mode definitions, instructions, and validation thresholds as typed data.
- Add Chinese, English, French, and automatic language controls without a user-facing
  model picker. There is no mixed setting: the hint is a single prior passed only to
  recognition, and deterministic processing derives script from the text itself
  (ADR 0004).

### Exit gate

The same captured transcript can be refined predictably by mode, and changing focus
during processing cannot change the session's mode.

## Phase 10: Persistence and history

- Add typed preferences with versioned storage and migrations.
- Store at most the product-defined ten recent history records.
- Preserve raw, normalized, and final text; model versions; timings; fallback reason;
  insertion outcome; source bundle ID; mode; and language hint.
- Add explicit local zero-edit feedback needed for dogfooding.
- Never persist audio, clipboard snapshots, or surrounding cursor content.

### Exit gate

History is bounded, migratable, resilient to corrupt data, and exposes raw/final
comparison without rerunning inference.

## Phase 11: Onboarding and permissions

- Guide microphone and Accessibility permission setup.
- Present model download, verification, preparation, recovery, and incompatibility
  states.
- Handle the required relaunch after Accessibility authorization.
- Keep onboarding policy in the app while permission and model-state details remain
  in their adapters.

### Exit gate

A clean installation can reach a ready state without Ollama, accounts, API keys, a
model picker, or an unexpected download triggered by starting dictation.

## Phase 12: Validation and dogfooding

- Run the full application compatibility matrix.
- Measure ASR CER/WER, written-quality zero-edit rate, insertion success, P50/P95
  stage and end-to-end latency, model load time, and memory on real inputs.
- Fix correctness, fallback, privacy, and lifecycle failures before cosmetic polish.
- Use the application daily for two weeks and record zero-edit feedback locally.

### Exit gate

The objective thresholds and two-week subjective gate in the spec are met with
recorded measurements. Results are not inferred from unit tests or synthetic inputs.

## Cross-cutting requirements

These apply from the first executable slice rather than being deferred phases:

- Every asynchronous result is scoped to a unique session ID.
- Mutable asynchronous resources are actor-isolated; UI-observable state is
  `@MainActor`; cross-boundary values are `Sendable`.
- Production logs never contain transcripts, audio, prompts with user content,
  clipboard contents, or cursor context.
- Refiner failure preserves deterministic text, and insertion failure leaves final
  text copyable.
- External dependencies and model artifacts require license review before adoption.
- Performance and quality claims require measurements from real inputs.

## Explicitly deferred

Do not add streaming insertion, meetings, file transcription, assistant mode, a
model picker, a prompt editor, custom vocabulary, cloud fallback, accounts, API keys,
remote telemetry, a daemon, or an XPC service as part of this sequence.
