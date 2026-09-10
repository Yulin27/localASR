<!-- Generated from Packages/LocalASRKit/Sources/AudioCapture/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Packages/LocalASRKit/Sources/AudioCapture/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# AudioCapture Guide

This module adapts macOS audio APIs and VAD to core audio ports.

## Owns

- Microphone engine lifecycle and input-device changes.
- Conversion to the canonical ASR format, initially 16 kHz mono PCM.
- Level events needed by the recording UI.
- VAD-based trimming, empty-audio detection, and optional segmentation hints.
- Bounded-memory or disk-backed capture for long dictation.

## Rules

- Recording begins and ends only from coordinator commands. VAD never ends the primary toggle-recording interaction.
- Never retain an unbounded `[Float]` for the duration of a long recording. Prefer bounded chunks or an ephemeral temporary file exposed through a core-owned audio reference.
- Keep the realtime audio callback free of blocking work, allocation-heavy transforms, model loading, persistence, and UI calls.
- Actor-isolate mutable engine state and make start/stop/cancel idempotent.
- Handle device removal, route changes, interruption, startup failure, and zero-frame capture explicitly.
- Delete temporary audio on success, cancellation, and failure unless an explicit debug policy retains it.
- Do not perform ASR, text processing, mode selection, or history writes here.

Use real recorded fixtures for audio conversion and VAD evaluation; quality benchmarks do not belong in ordinary network-free unit tests.

