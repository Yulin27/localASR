# LocalASRKit Package Guide

This package contains the testable product core and all infrastructure adapters. It targets macOS 15 or later and uses Swift 6 language mode.

## Dependency graph

- `DictationCore` and `Observability` have no internal target dependencies.
- `AudioCapture` and `MacIntegration` depend only on `DictationCore` and `Observability`.
- `ModelManagement` depends only on `DictationCore` and `Observability`.
- `SpeechEngines` and `TextProcessing` may additionally depend on `ModelManagement`.
- `Persistence` depends only on `DictationCore` and `Observability`.
- No package target may import or depend on the application shell.

If a dependency would point in the opposite direction, introduce a value or port in `DictationCore` instead. Do not solve cycles with globals or notification broadcasts.

## Swift conventions

- Use Swift 6 language mode and strict concurrency-safe designs.
- Public API should be minimal and documented. Prefer structs and enums for values, protocols for ports, actors for mutable resources, and final classes only where framework interop requires them.
- Do not use `@unchecked Sendable` without a documented synchronization proof and focused concurrency tests.
- Provider SDK types remain internal to their adapter module.
- Prefer `Clock`-based injected time and deterministic fakes over sleeps in tests.
- Add external package dependencies only after license review and a measured need. Pin an intentional version range or exact revision.

## Verification

Run from the repository root:

```sh
swift build --package-path Packages/LocalASRKit
swift test --package-path Packages/LocalASRKit
```

Standard tests must not require microphone permission, Accessibility permission, network access, or model downloads.
