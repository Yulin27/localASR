<!-- Generated from Packages/LocalASRKit/Sources/MacIntegration/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Packages/LocalASRKit/Sources/MacIntegration/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# MacIntegration Guide

This module adapts global shortcuts, foreground application capture, Accessibility, clipboard, permissions, and login-item APIs.

## Shortcut semantics

- Emit one semantic activation per completed shortcut press. Filter keyboard auto-repeat and duplicate event-tap delivery.
- First activation while idle starts recording; the next activation while recording stops it. Key release has no stop behavior.
- The adapter reports activation intent only. The coordinator decides whether the current phase accepts it.

## Target capture and insertion

- Capture the source PID, bundle ID, focused Accessibility element or durable target token before showing an overlay or awaiting work.
- Attempt delivery in this order: Accessibility selected-text write, clipboard plus simulated paste, copy-only fallback.
- Return a structured outcome. Posting Command-V means `pasteRequested`; it does not prove the target consumed the text.
- A clipboard transaction snapshots all items and types, marks ownership with a private session value, and restores only if it still owns the pasteboard. Never overwrite newer user clipboard data.
- Handle unsupported AX attributes, invalidated elements, unresponsive targets, missing permission, Secure Input, keyboard-layout differences, and password fields without losing final text.
- UI panels created here must not become key/main windows or steal Accessibility focus.

## Permissions

- Expose typed permission state and navigation/request actions. Do not encode onboarding copy or UI policy here.
- Permission checks and insertion integration require dedicated tests plus the manual application matrix in the test guide.

