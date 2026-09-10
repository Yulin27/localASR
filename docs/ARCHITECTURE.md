# LocalASR Architecture

## Status

This document defines the intended v0.1 structure. The Swift targets currently contain compile-safe placeholders only. Runtime APIs should be introduced incrementally through tested vertical slices.

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

Only one dictation session may be active. Each asynchronous callback carries a session ID, and stale callbacks cannot mutate current state.

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
| `DictationCore` | Domain values, port protocols, state machine, orchestration, fallback policy | UI, AppKit, AVFoundation, ML runtimes, persistence implementation |
| `AudioCapture` | Microphone lifecycle, PCM conversion, bounded or disk-backed long recording, audio buffers, VAD adapter | ASR selection, text processing, UI state |
| `SpeechEngines` | ASR provider adapters and provider result mapping | Recording, refinement, insertion, settings UI |
| `TextProcessing` | Ordered deterministic transforms, local refiner adapters, output guards | Audio, hotkeys, clipboard |
| `MacIntegration` | Hotkeys, application/target capture, AX insertion, pasteboard transaction, permissions, login item | Product pipeline policy |
| `ModelManagement` | Model manifest, pinned revisions, download, verification, preparation, cache/residency | Provider selection UI or dictation orchestration |
| `Persistence` | Preferences and recent-history implementations, migrations | UI and pipeline decisions |
| `Observability` | Privacy-safe logs, signposts, stage timing, memory measurements | User text and audio payloads |
| `App` | SwiftUI/AppKit presentation and composition root | Model implementation or domain policy |

`DictationCore` is the stable center. Infrastructure implements its ports. The application constructs concrete adapters and injects them into the coordinator.

## Planned ports

The first core pass should define only capabilities required by the v0.1 pipeline:

- `AudioCapturing`
- `VoiceActivityDetecting`
- `SpeechRecognizing`
- `DeterministicTextProcessing`
- `TextRefining`
- `TextInserting`
- `ActiveApplicationProviding`
- `ModeResolving`
- `HistoryStoring`
- `MetricsRecording`

Streaming recognition and streaming insertion are separate future capabilities. They should not inflate the batch protocols.

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

The coordinator must be tested with fakes before real model integration. Cancellation and failure are tested at every await boundary.

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
