<!-- Generated from Packages/LocalASRKit/Sources/DictationCore/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Packages/LocalASRKit/Sources/DictationCore/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# DictationCore Guide

This is the stable domain and application-policy center.

## Owns

- Session IDs, immutable session context, audio/transcript references, modes, languages, results, failures, and structured insertion outcomes.
- Narrow port protocols required by the v0.1 workflow.
- The single dictation coordinator and its explicit phase transitions.
- Cancellation, stale-result rejection, retry eligibility, and fallback policy.

## Rules

- Import Foundation only. Never import SwiftUI, AppKit, AVFoundation, CoreML, MLX, os logging, or a provider SDK.
- Do not read `UserDefaults`, environment variables, the pasteboard, the clock, or the filesystem directly. Receive values and capabilities through initialization or ports.
- The first accepted shortcut activation creates a session; the second activation for that recording session freezes capture and advances to transcription. Key-up and auto-repeat are not domain actions.
- Freeze target application, insertion destination, language hint, mode, and preferences at session start.
- Model active runtime resources separately from public state snapshots; do not embed framework objects in domain enums.
- Require every callback/result to carry or be scoped to a session ID.
- Preserve `rawText`, `normalizedText`, and `finalText` separately in result values.
- Keep streaming capabilities out of the initial batch ports. Add separate protocols if streaming enters the accepted scope.
- Errors are typed by stage and recoverability. Do not expose provider error strings as domain decisions.

Coordinator tests belong under the package test target and must use fakes for every port.

