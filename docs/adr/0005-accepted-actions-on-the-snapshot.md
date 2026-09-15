# ADR 0005: The coordinator publishes the actions it accepts

- Status: Accepted
- Date: 2026-09-15
- Amends: [ADR 0003](0003-core-contracts-and-coordinator.md) §1 and §4. It does not supersede it.

## Context

Phase 2 adds the first view that sends actions: the menu-bar extra shows Start or Stop, Cancel,
and Dismiss. A view needs to know which of them apply, and the obvious source is the published
phase. That source is wrong in a way the view cannot detect.

The coordinator decides actions from different state than the snapshot shows:

- `toggleRecording` and `cancel` decide from `active`, the session in flight.
- `dismiss` decides from the published phase.
- `finalize` clears `active` before it awaits the device release and the history write, and only
  then publishes the terminal snapshot (ADR 0003 §4 and its consequences). During that window the
  snapshot still reads the last processing phase, while the coordinator would already start a new
  session on an activation and would ignore a cancel.

A view deriving commands from the phase would offer Cancel for a session the coordinator has
already let go of, and hide the Start the coordinator would honour. The window lasts as long as a
history store takes to write, which is unbounded in principle.

## Decision

### 1. Accepted actions are a coordinator output

`SessionSnapshot` carries `acceptedActions: AcceptedActions`: what `toggleRecording` would do
(`start`, `stop`, or `ignored`), whether `cancel` applies, and whether `dismiss` applies.

The coordinator stamps it in its single `publish` path, from the same state the action handlers
read. No snapshot reaches an observer without it. Views render it and never derive it from the
phase. `AcceptedActions(settledIn:)` exists as a default for snapshots built outside the
coordinator, such as previews and tests; the coordinator never uses it.

A coordinator that has shut down reports `.nothing`, because `handle(_:)` ignores every action
after `shutdown()`.

### 2. Clearing `active` publishes a same-phase refresh

When `finalize` clears `active` for a session that still owns the published state, it republishes
the current snapshot with recomputed actions, in the same actor step and before the cleanup
suspends. The phase and the session ID are unchanged. The terminal snapshot still follows the
history write, so ADR 0003's ordering guarantee — history is readable when the terminal phase is
observed — holds as before.

A completed session therefore publishes its last processing phase twice:

```text
idle, preparing, recording, transcribing, normalizing, refining, inserting, inserting, completed
                                                                            ^ refresh
```

### 3. The pre-freeze window stays unpublished

Between an activation and the moment the new session freezes its context, nothing may be published
(ADR 0003 §5). The snapshot on screen still belongs to the previous session, and so do its accepted
actions. An action sent in that window is still decided by the coordinator against the session
actually in flight: a toggle stops it, a cancel cancels it. Only a command's label can be stale,
and only for the time target capture and settings take.

## Consequences

- Command availability has one owner. A view that shows Start, Stop, Cancel, or Dismiss agrees
  with what the coordinator will do, except in the pre-freeze window above.
- Observers must tolerate a snapshot whose phase and session equal the previous one's. A view that
  runs an entrance animation or opens a panel on a phase *change* has to compare phases rather than
  treat every snapshot as a transition. `RecordingOverlay` in Phase 3 is the first such observer.
- Tests that assert an exact phase sequence include the refresh explicitly.
- Stage timings and metrics are unaffected: the refresh closes no timing and reads no clock.

## Alternatives considered

- **Views derive commands from the phase.** No new API, but wrong for the whole cleanup window, and
  it duplicates the coordinator's decision table in the application shell.
- **Publish the terminal snapshot before the history write.** Closes the window without a refresh,
  but breaks the guarantee that history is readable when a session is observed to end.
- **Keep `active` set until the terminal snapshot.** Makes the phase and the decision agree, but
  brings back the defect ADR 0003 fixed: a slow history store would stop the user from dictating
  again.
- **Decide `toggleRecording` from the published phase.** Same defect as the previous alternative,
  seen from the other side.
- **A separate stream of accepted actions.** Two streams can be observed out of step; one value on
  the snapshot cannot.
