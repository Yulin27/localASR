# ADR 0001: Native modular monolith with ports and adapters

- Status: Accepted
- Date: 2026-09-10

## Context

The product needs macOS-specific recording, global shortcuts, Accessibility insertion, local ASR, deterministic text processing, and local LLM refinement. ASR and LLM runtimes are evolving, while the dictation workflow and product policies should remain stable and easily testable.

A single unstructured application target would be initially fast but would allow UI, audio, inference, settings, and insertion responsibilities to accumulate in shared service objects. A multi-process design would improve isolation but add IPC, signing, deployment, and lifecycle work before those benefits are proven necessary.

## Decision

Build one native Swift application process backed by a local modular Swift package. Put domain values, port protocols, and the session coordinator in `DictationCore`. Put macOS and model implementations in separate adapter modules whose dependencies point toward the core.

Use actor isolation for mutable asynchronous runtime resources and `@MainActor` only for UI-observable state. Keep batch protocols narrow and introduce separate protocols for future streaming capabilities.

## Consequences

- Core workflow and fallback behavior can be tested without microphone, Accessibility permission, or model weights.
- ASR and refinement runtimes can be benchmarked and replaced without changing the UI or coordinator.
- Package targets impose more initial structure and require intentional dependency wiring.
- In-process model failure can affect the app. XPC isolation remains a later adapter-level option if measurements justify it.

## Alternatives considered

- One application target with folders only: rejected because boundaries would be conventional rather than enforced.
- XPC model service from the beginning: deferred because it adds operational complexity to v0.1.
- Local HTTP daemon: rejected for v0.1 because it adds another lifecycle and security surface without a cross-platform requirement.

