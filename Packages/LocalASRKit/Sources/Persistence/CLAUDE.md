<!-- Generated from Packages/LocalASRKit/Sources/Persistence/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Packages/LocalASRKit/Sources/Persistence/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# Persistence Guide

This module implements core storage ports for preferences, recent history, and migrations.

- Keep settings keys and storage-framework types private to this module. Expose typed values through ports.
- Use versioned schemas and explicit migrations. Writes must be atomic and actor-isolated.
- The v0.1 history is bounded to the product-defined recent count. Do not grow an analytics database implicitly.
- A history record may include raw, normalized, and final text; source bundle ID; language/mode; model versions; stage durations; fallback reason; insertion outcome; and explicit zero-edit feedback.
- Do not persist microphone audio, surrounding cursor content, clipboard snapshots, or credentials in history.
- Never log stored transcript fields. Tests use temporary directories or in-memory stores and must clean up their own fixtures.
- Preferences and history are separate concerns and may use different backends.
- Keychain-backed secrets belong in a dedicated credential adapter only if a future accepted feature requires them; v0.1 has no API keys.

