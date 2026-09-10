# ADR 0002: Toggle recording is the primary interaction

- Status: Accepted
- Date: 2026-09-10

## Context

Users may dictate long passages. Requiring a shortcut to remain held is uncomfortable, increases accidental interruption risk, and incorrectly couples keyboard state to recording duration.

## Decision

A complete global-shortcut activation while idle starts a recording session. The next activation while recording stops capture and advances that same session to transcription. Releasing the shortcut does not stop recording.

Keyboard auto-repeat and duplicate events are filtered before they reach the coordinator. VAD may trim silence, reject empty audio, or support internal long-audio segmentation, but it does not automatically finish the primary v0.1 recording interaction.

The destination application and insertion target are captured on the first activation and remain frozen until delivery or cancellation.

## Consequences

- Long dictation does not require holding a key.
- Recording storage must remain bounded in memory, using a temporary file or bounded chunks when appropriate.
- The overlay must make the persistent recording state and the second-press stop action unambiguous.
- Hotkey tests must cover auto-repeat, debouncing, rapid double activation, and stop behavior.
- ASR may process long recordings in chunks internally, but v0.1 still produces and inserts one final result rather than streaming text into the target.

