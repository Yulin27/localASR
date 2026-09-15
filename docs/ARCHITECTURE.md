# LocalASR Architecture

## Status

This document defines the intended v0.1 structure.

`DictationCore` is implemented: the domain values, the port protocols, the refinement output
guard, and the `DictationCoordinator` all exist and are covered by tests that run against
fakes with no microphone, Accessibility permission, network, or model. The seven adapter
modules still contain placeholders, and no runtime API has been chosen yet. Adapter behaviour
should be introduced incrementally through tested vertical slices.

The application shell exists: a signed menu-bar app generated from `App/project.yml`
(ADR 0006). Debug builds run a real coordinator over the scripted `DictationDemo`
adapters, with a demo scenario picker in the menu; Release builds report that dictation
is unavailable until Phase 3 supplies real adapters.

## Architectural style

LocalASR is a native macOS modular monolith with ports and adapters. It ships as one application process for v0.1.

The architecture has three goals:

1. Keep the dictation workflow independent from model and macOS APIs.
2. Make ASR, refinement, and insertion implementations replaceable.
3. Make cancellation, fallback, privacy, and latency observable at session level.

## Runtime flow

```text
Global shortcut toggle / menu-bar command
                 |
                 v
        MainActor AppModel
                 |
                 v
       DictationCoordinator actor
                 |
       capture frozen session context
                 |
                 v
        AudioCapture -> AudioClip
                 |
                 v
          VAD trim / validation
                 |
                 v
      SpeechRecognizer -> raw text
                 |
                 v
       DeterministicTextPipeline
                 |
                 v
          TextRefiner by mode
                 |
                 v
        RefinementOutputGuard
          | valid        | invalid/error/timeout
          v              v
       refined text   deterministic text
                 \       /
                  v     v
                 TextInserter
                       |
                       v
              History + stage metrics
```

The first shortcut activation starts recording and the second activation finishes it. Key release has no lifecycle meaning. VAD trims silence, rejects empty captures, and may help segment long audio for ASR, but it never ends the primary recording interaction in v0.1.

## Session lifecycle

The coordinator exposes immutable state snapshots for UI rendering. Runtime resources remain private to the coordinator and adapters.

```text
idle
 -> first shortcut activation
 -> preparing
 -> recording
 -> second shortcut activation
 -> transcribing
 -> normalizing
 -> refining
 -> inserting
 -> completed
 -> idle

Any active phase -> cancelled -> idle
Any active phase -> failed -> idle/retry
```

Voice activity detection shares the `.transcribing` phase. The lifecycle gives it no step of
its own, and nothing user-visible changes between trimming silence and running recognition; a
voice-activity failure is reported at `.transcribing`.

The coordinator accepts three semantic actions — `toggleRecording`, `cancel`, and `dismiss`.
A second activation ends recording, an activation during processing is ignored, and an
activation from a finished session starts a new one. `handle(_:)` is synchronous: it mutates
state and returns while the pipeline runs in a task of its own, which is what lets a
cancellation arrive while a long recognition call is still in flight.

Only one dictation session may be active. Every phase change goes through a single choke point
that rejects a run whose session was superseded or whose task was cancelled, so a late
adapter result cannot mutate current state even when the adapter ignores cancellation.

Shortcut input is debounced at the adapter boundary. Keyboard auto-repeat and modifier/key release events cannot start, stop, or create duplicate sessions.

The following context is captured at recording start and remains fixed:

- Session ID and start time
- Source process and bundle ID
- Native insertion target identity
- Selected or automatically resolved language hint
- Per-application refinement mode
- Relevant immutable preferences

## Module map

| Module | Owns | Must not own |
|---|---|---|
| `DictationCore` | Domain values, port protocols, state machine, orchestration, fallback policy, refinement output validation | UI, AppKit, AVFoundation, ML runtimes, persistence implementation |
| `AudioCapture` | Microphone lifecycle, PCM conversion, bounded or disk-backed long recording, audio buffers, VAD adapter | ASR selection, text processing, UI state |
| `SpeechEngines` | ASR provider adapters and provider result mapping | Recording, refinement, insertion, settings UI |
| `TextProcessing` | Ordered deterministic transforms, local refiner adapters, thinking/preamble cleanup inside those adapters | Audio, hotkeys, clipboard, output validation (the guard is core-owned) |
| `MacIntegration` | Hotkeys, application/target capture, AX insertion, pasteboard transaction, permissions, login item | Product pipeline policy |
| `ModelManagement` | Model manifest, pinned revisions, download, verification, preparation, cache/residency | Provider selection UI or dictation orchestration |
| `Persistence` | Preferences and recent-history implementations, migrations | UI and pipeline decisions |
| `Observability` | Privacy-safe logs, signposts, stage timing, memory measurements | User text and audio payloads |
| `App` | SwiftUI/AppKit presentation and composition root | Model implementation or domain policy |

`DictationCore` is the stable center. Infrastructure implements its ports. The application constructs concrete adapters and injects them into the coordinator.

## Ports

The capabilities the v0.1 pipeline needs, all defined in `DictationCore`:

| Port | Note |
|---|---|
| `AudioCapturing` | `prepare()` warms the capture path; the coordinator calls it during `preparing`. |
| `VoiceActivityDetecting` | Returns a frame range into the existing clip, not a second clip. |
| `SpeechRecognizing` | Batch. An adapter may chunk internally and still return one result. |
| `DeterministicTextProcessing` | Always runs. Receives the mode, because punctuation and list handling are mode-dependent. |
| `TextRefining` | Returns unvalidated output; see the guard below. |
| `TextInserting` | Never throws. Delivery is reported through a structured outcome. |
| `ActiveApplicationProviding` | Never throws. A missing permission degrades delivery rather than aborting a recording. |
| `ModeResolving` | Synchronous and pure, so a mode can be resolved and frozen before focus changes. |
| `HistoryStoring` | Storage backend is a later decision. |
| `MetricsRecording` | Non-throwing. Receives counts, durations, and categories, never text. |
| `DictationSettingsProviding` | Supplies the language hint, default mode, and refinement toggle that the session freezes. |
| `TimeSource` | Wall-clock and monotonic readings together, so timings are testable without sleeping. |

Two capabilities are deliberately *not* ports:

- **The refinement output guard** is a concrete core type configured by a
  `RefinementGuardPolicy` value. It sits outside `TextRefining` so a model adapter cannot
  certify its own output, and it is not a protocol so no composition root can install a
  weaker rule set. Only the per-mode thresholds vary.
- **Session identity** arrives as an injected `SessionIDGenerator` rather than a port,
  because it is a value source rather than a capability with behaviour.

Streaming recognition and streaming insertion are separate future capabilities. They should
not inflate the batch protocols.

## Observing the coordinator

`DictationCoordinator` exposes `currentSnapshot()` for a synchronous read and
`snapshots() -> AsyncStream<SessionSnapshot>` for observation. Each call to `snapshots()`
returns a stream of its own, so several views observe independently, and the current
snapshot is delivered on subscribe so a late observer never renders a stale state. The
buffer is unbounded: dropping to the newest snapshot would be fine for rendering but would
make the sequence of phases unobservable, and a session produces only a handful of small
snapshots. `shutdown()` terminates every stream explicitly, because an actor's `deinit`
runs outside its isolation and cannot touch the subscriber list.

Each snapshot carries `acceptedActions`: what `toggleRecording` would do (start, stop, or
nothing), and whether `cancel` and `dismiss` apply. The coordinator stamps it from its own
state when it publishes, and views render commands from it rather than from the phase,
because the two diverge while a finished session cleans up. Clearing the in-flight session
publishes a same-phase refresh, so observers must tolerate a snapshot whose phase and session
repeat the previous one. The only window in which the published actions lag is a new
session's pre-freeze window, where nothing may be published; an action sent then is still
decided against the session actually in flight. See ADR 0005.

Snapshots never carry the audio clip, only `AudioClipMetadata`. The clip is owned by the
session and released in the coordinator's finalize path on **every** route out of a session,
including the one where a late adapter returns after its session was superseded.

## Text representation

The pipeline preserves distinct stages:

- `rawText`: direct ASR result
- `normalizedText`: deterministic output
- `finalText`: accepted refinement or deterministic fallback

Each deterministic transform has an identifier and version. The ordered pipeline should initially cover Unicode cleanup, ASR artifacts, ITN, filler words, punctuation, mixed-script spacing, and conservative self-correction handling.

The local refiner receives isolated instructions, one transcript, one mode, and no tools or conversation history. Its output is accepted only after mode-specific validation. Invalid, empty, excessively expanded, or contaminated output falls back to `normalizedText`.

## Insertion transaction

The destination is captured before any overlay or asynchronous work can change focus. Delivery tries:

1. Accessibility selected-text replacement.
2. A clipboard transaction followed by a simulated paste.
3. Copy-only fallback with user-visible notification.

Clipboard restoration snapshots all pasteboard items and types. It restores only if the pasteboard is still owned by that insertion session, preventing overwriting content copied by the user during inference.

Insertion returns a structured result such as direct write, paste requested, copied only, or failure. A synthetic paste event is not considered confirmation that the target accepted the text.

## Model lifecycle

Model installation and dictation are separate workflows. Onboarding or background preparation downloads a pinned artifact, verifies it, compiles or prepares it, and records readiness. Starting a dictation must never unexpectedly begin a large model download.

Recording duration is not coupled to holding a key. Capture must remain bounded in memory, and an ASR adapter may perform internal chunking for long input while still returning one final transcript to the core pipeline.

A model manifest records at least:

- Stable model and provider identifiers
- Upstream revision
- Artifact URLs and checksums
- Quantization and expected files
- Disk and approximate memory requirements
- Model and data licenses
- Minimum OS and hardware requirements

v0.1 keeps inference in process. An XPC adapter can be considered later if crash isolation or model memory reclamation proves necessary; the core ports should make that change transparent.

## Persistence and privacy

Preferences, history, and model state use separate stores. Recent history is versioned and bounded by product policy. Audio is ephemeral unless a future explicit feature changes that policy.

A history record should be able to capture:

- Raw, normalized, and final text
- Source application bundle ID
- Mode and language hint
- ASR and refiner identifiers/versions
- Stage timings and fallback reason
- Insertion outcome
- Optional explicit zero-edit feedback

Production logs contain identifiers, durations, sizes, phases, and error categories, never transcript text, audio, clipboard contents, or cursor context.

## Testing strategy

1. Pure unit tests for state transitions, fallback policy, and deterministic transforms.
2. Contract tests that every adapter must pass.
3. Integration tests with recorded multilingual audio and a controlled editable target.
4. Manual compatibility tests across the product matrix.
5. Performance runs recording P50/P95 stage latency, peak memory, model load time, and insertion outcome.

The coordinator must be tested with fakes before real model integration. Cancellation and failure are tested at every await boundary. This is implemented: `DictationCoreTests` drives complete sessions against deterministic fakes with an injected clock, including a cancellation parked at each of the ten await boundaries, an adapter that ignores cancellation, and the full fallback matrix.

## Repository layout

```text
App/                         SwiftUI/AppKit shell and feature UI
Packages/LocalASRKit/        Local modular Swift package
  Sources/DictationCore/
  Sources/AudioCapture/
  Sources/SpeechEngines/
  Sources/TextProcessing/
  Sources/MacIntegration/
  Sources/ModelManagement/
  Sources/Persistence/
  Sources/Observability/
  Tests/
ModelAssets/                 Manifest only; downloaded weights are ignored
Scripts/                     Repeatable build, benchmark, and release helpers
docs/adr/                    Architecture decision records
```

## Deferred decisions

- Exact ASR runtime and quantization, pending on-device corpus benchmarks
- Exact local refiner model and residency policy
- Native Swift ITN scope versus a later C++ FST bridge
- Persistence backend beyond the bounded v0.1 history
- Streaming and XPC isolation

These choices must remain behind the defined ports until measured evidence justifies an ADR.
