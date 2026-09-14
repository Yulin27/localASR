# ADR 0003: Core contracts and coordinator ownership

- Status: Accepted
- Date: 2026-09-10

## Context

Phase 1 of `IMPLEMENTATION_PLAN.md` defines the stable center that every later phase implements
against. Three questions came up while writing it that are durable rather than incidental: what
the coordinator's action set is, where refinement output is judged, and who owns a captured
recording. Each was decided in `DictationCore` and each constrains phases 3–10, so they are
recorded here rather than left in the code.

## Decision

### 1. Three semantic actions, and no retry

`DictationAction` is `toggleRecording`, `cancel`, `dismiss`. A second activation ends recording;
an activation during transcription, normalisation, refinement, or insertion is ignored, because
there is no recording left to stop and starting a second session would abandon text the user has
already spoken. A finished session holds its terminal phase until dismissed, so the UI can show
the outcome and the copy-only fallback; an activation from a terminal phase starts a new session.

`ARCHITECTURE.md` sketches `failed -> idle/retry`. Retry is deliberately **not** implemented.
Re-running a failed stage would require retaining that stage's inputs until the user decides —
including the captured clip — which contradicts the rule that audio is ephemeral. A failed
session is recoverable by dictating again, which costs the user one more press and keeps every
resource releasable the moment its stage ends.

### 2. The refinement output guard is core-owned, concrete, and outside `TextRefining`

A transcript's refinement is judged by `RefinementOutputGuard` in `DictationCore`. It is not part
of `TextRefining`, and it is not a port.

Keeping it out of `TextRefining` means a model adapter never certifies its own output. Making it
a concrete type rather than a protocol means a composition root — including a preview or test
assembly — cannot install a weaker rule set either. Only the thresholds vary, through an injected
`RefinementGuardPolicy` whose limits are per mode, because structured output is legitimately
longer than its input while a message is not.

The coordinator owns the call site and therefore owns the fallback: a rejected or failed
refinement sets `finalText` to the deterministic text and records a `FallbackReason`.

### 3. The session owns its recording, and releases it on every route out

`AudioClip` is a reference-shaped protocol with `loadSamples()` and `discard()`, not a value
holding samples. `ARCHITECTURE.md` requires capture to stay bounded in memory and to support
disk-backed long recordings, and a value type would force such an adapter to materialize every
frame it owns.

The clip is private to the coordinator's session state. It never enters a snapshot — snapshots
carry `AudioClipMetadata` — and it is released in the finalize path on **every** route out of a
session, including the route where an adapter that ignores cancellation returns after its session
has already been superseded. Allowing in-process release alone was rejected because the reference
would then depend on the pipeline reaching its end, which is exactly what a cancellation
prevents.

### 4. A cancellation is answered immediately, not when the adapter returns

`cancel` publishes `.cancelled` and releases the session in the same turn the user asks for it.
Cancelling the task does not stop an adapter that never checks for cancellation, and a recognition
call on a long recording can take tens of seconds to return. Waiting for it would leave the user
watching `transcribing`, with the next activation landing in the ignored processing branch and no
way to start dictating again.

The abandoned run keeps only its cleanup. It no longer owns the published state, so it releases the
device, discards the clip, writes any history the session earned, and records its metrics without
publishing anything. This is why a run tracks its own phase separately from the published snapshot:
the snapshot is a projection for the UI, and after a cancellation the two legitimately disagree.

A consequence worth stating plainly: a terminal snapshot no longer proves the run behind it has
finished unwinding. Metrics are recorded once, at the end of that cleanup, and are the signal that
it has.

### 5. The mode is resolved from the frontmost application, not from the destination

`ModeResolving` takes the `ActiveApplication` frozen at recording start, not the `InsertionTarget`.
`Spec.md` keys per-application modes on the frontmost bundle identifier, and reading which
application is frontmost needs no Accessibility permission, while resolving a focused element does.
Taking the destination would silently fall back to the default for every session whose focused
element could not be resolved — exactly the sessions where the permission is not yet granted, or
the destination is a password field, which are the ones a per-application rule is most needed for.

For the same reason nothing is published until the context is frozen. `ARCHITECTURE.md` requires
the destination to be captured before any overlay or asynchronous work can change focus, and the
first snapshot a view can react to therefore already carries it.

## Consequences

- Long dictation holds one clip and one transcript at a time; nothing accumulates across sessions.
- A cancellation is honoured at every await boundary, including inside insertion — the one port
  that cannot report cancellation by throwing, so the coordinator checks explicitly.
- A history record is written whenever text reached insertion, not only when the session
  completed. Text handed to the inserter may be in the user's document even if the session was
  cancelled while that happened, and the history entry is then the only remaining record of it.
  It is written from a context that does not inherit the session's cancellation, because a store
  doing file or database I/O would otherwise refuse the write that matters most.
- A lost history write never fails a dictation that already delivered, but it is reported as a
  `FallbackReason` on the snapshot and in metrics. A store failing every write must be visible.
- Phase 3 may add a warm/idle refresh policy on top of `AudioCapturing.prepare()` without
  changing the port, and the AUHAL decision expected in that phase does not affect these
  contracts.
- Phase 6 and Phase 9 can tune refinement limits and per-application mode bindings as typed data,
  without touching the coordinator.
- Re-running a single stage remains unavailable; a user who loses a session mid-pipeline dictates
  again.

## Alternatives considered

- **Validation inside `TextRefining`'s return value**: fewer types, but the guard and the thing it
  guards would sit behind one protocol, so a buggy or over-eager adapter could bypass it.
- **The guard as a protocol port**: would let any assembly supply a weaker implementation, which
  is the same self-certification hazard from the other side.
- **An eager `[Float]` clip value**: simpler at the call site, but it forces any disk-backed
  capture adapter to materialise the whole recording, and it puts megabytes of PCM into the state
  machine that snapshots are copied from.
- **Retry from the failed stage**: would require holding a clip past its session and would make
  cleanup depend on a user decision rather than on the session ending.
