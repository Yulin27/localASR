<!-- Generated from Packages/LocalASRKit/Sources/DictationDemo/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Packages/LocalASRKit/Sources/DictationDemo/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# DictationDemo Guide

Scripted adapters that let the application shell, previews, and application tests drive a real
`DictationCoordinator` before real adapters exist.

## Owns

- `DemoScenario` and the selector that fixes one scenario per session.
- Scripted implementations of every coordinator port, paced by an injected `Clock`.
- `ManualClock`, so tests outside this package can pace the same adapters deterministically.
- The factory that returns `DictationCoordinator.Dependencies` for a selector and a clock.

## Rules

- Depend on `DictationCore` only. No other package target may depend on this one.
- Never touch a microphone, the pasteboard, the Accessibility API, the network, the filesystem, or
  a model. A scenario describes an outcome; it does not perform one.
- Read time only from the injected clock. Do not sleep on a real clock inside an adapter.
- Keep demo output recognisably scripted: engine identifiers, transform identifiers, and audio
  origin must never look like a real provider or a microphone.
- The application selects this assembly in Debug only. Nothing here may be presented as a working
  Release build.
- The latch-based coordinator fakes stay in `DictationCoreTests`; do not move them here.

Run from the repository root:

```sh
swift build --package-path Packages/LocalASRKit
swift test --package-path Packages/LocalASRKit
```
