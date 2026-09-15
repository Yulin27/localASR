<!-- Generated from App/Features/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing App/Features/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# Application Feature Guide

This guide applies to all UI features below this directory.

- Feature folders contain presentation models, views, and AppKit presentation wrappers only.
- Views send semantic actions such as start/stop, retry, copy, or open settings. They do not call low-level adapters directly.
- `MenuBar` shows status and exposes primary commands without owning dictation state.
- `RecordingOverlay` visualizes persistent toggle-recording and processing states. It must not take focus or stop recording on key release.
- `Onboarding` guides microphone and Accessibility authorization, model preparation, and the required relaunch or recovery paths.
- `Settings` edits typed settings through an injected store; it does not read or write raw preference keys.
- `History` presents bounded records and raw/normalized/final comparisons; it never reruns inference implicitly.
- Add accessibility labels and keyboard descriptions for all status-only visuals and controls.
- Keep business logic testable outside SwiftUI before adding snapshot or UI tests.

