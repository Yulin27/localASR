# LocalASRKit Test Guide

Tests should prove state, fallback, and boundary behavior without requiring privileged macOS access or model downloads.

## Required coverage

- Coordinator: start, second-press stop, duplicate/repeated shortcut events, every valid phase transition, cancellation at each await boundary, stale callbacks, and idempotent cleanup.
- Audio: conversion, empty input, bounded long capture, temporary-file cleanup, route changes, and failures.
- ASR contracts: preparation, language hints, cancellation, long-input ordering, empty/failed results, and provider-to-core mapping.
- Text: per-transform multilingual fixtures, transform order, mode validation, thinking/preamble cleaning, timeout, and deterministic fallback.
- Insertion: AX success, paste fallback, copy-only fallback, invalid target, permission failure, and clipboard ownership-safe restoration.
- Persistence: bounded history, atomic writes, migrations, corrupt data, and privacy-sensitive fields.

## Test design

- Use deterministic fakes for ports and an injected clock; avoid arbitrary sleeps.
- Standard package tests must not access the network, microphone, real pasteboard, Accessibility APIs, or downloaded weights.
- Keep real-model and real-audio benchmarks in an explicit opt-in suite or script. Never fabricate audio or quality results.
- Store curated Chinese, English, French, and mixed-language fixtures with their provenance and expected intent.
- Maintain a manual insertion matrix for Chrome, VS Code, Slack, Notion, Mail, Terminal, Cursor, WeChat, and password fields.

Run from the repository root:

```sh
swift build --package-path Packages/LocalASRKit
swift test --package-path Packages/LocalASRKit
```

