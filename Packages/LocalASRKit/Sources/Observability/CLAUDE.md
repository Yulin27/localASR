<!-- Generated from Packages/LocalASRKit/Sources/Observability/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Packages/LocalASRKit/Sources/Observability/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# Observability Guide

This module provides privacy-safe operational visibility.

- Record session IDs, phases, stage durations, model identifiers/versions, byte/sample counts, memory measurements, insertion outcome categories, and typed error categories.
- Never record transcript text, audio, prompts containing user content, clipboard content, cursor context, or selected text.
- Use unified logging for diagnostics and signposts/continuous clocks for performance measurements.
- Keep logging and metrics best-effort; observability failure must not change pipeline behavior.
- Make sinks injectable so tests can assert events without scraping logs.
- Define stable event names and units. Distinguish model preparation, cold inference, warm inference, and end-to-end latency.
- Local self-evaluation metrics remain local. Adding remote telemetry requires an explicit product and privacy decision.

