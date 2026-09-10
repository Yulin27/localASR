# LocalASR Agent Guide

This file defines repository-wide rules. More specific `AGENTS.md` files exist under the application, package modules, tests, model assets, scripts, and documentation. Read every guide from the repository root down to the directory you are changing; the nearest guide adds local detail.

## Read first

Before changing code, read:

1. `Spec.md` for product scope and acceptance criteria.
2. `docs/ARCHITECTURE.md` for system boundaries and data flow.
3. Relevant records in `docs/adr/` for accepted technical decisions.
4. The nearest scoped `AGENTS.md` for the files being changed.

## Current state

The repository is an architecture scaffold, not yet a functioning application. The local Swift package builds, but its targets contain module markers only. There is no Xcode application project and no ML runtime dependency has been selected.

## Product invariants

- Build a native Swift/SwiftUI menu-bar application for macOS 15 or later, with Apple Silicon as the first supported hardware.
- Recording uses a toggle shortcut: press once to start, speak for as long as needed, and press again to stop. Key release never stops recording.
- Capture the target application and insertion destination when recording begins.
- Keep audio, ASR, deterministic processing, and LLM refinement local. Cloud fallbacks, accounts, API keys, and telemetry are out of scope unless the spec changes.
- Chinese, English, French, and mixed-language dictation are first-class requirements.
- Written-quality output is the product core. Preserve raw, deterministic, and final text as distinct values.
- v0.1 delivers one final result. Do not add streaming insertion, meetings, file transcription, assistant mode, a model picker, or a prompt editor without changing the spec.
- The app owns model selection, installation, and preparation; users do not configure model infrastructure in v0.1.

## Repository-wide engineering rules

- Use the accepted modular-monolith and ports/adapters design. Do not add a daemon, XPC service, or second process for v0.1.
- Only the dictation coordinator advances session phases. UI and adapters report inputs and results; they do not orchestrate the workflow.
- Every session has a unique ID. Ignore stale callbacks after cancellation or replacement.
- Use Swift concurrency deliberately: UI state on `@MainActor`, mutable asynchronous resources in actors, and cross-boundary values conforming to `Sendable`.
- Wire concrete dependencies in the application composition root. Avoid service locators, mutable global singletons, and domain reads from global preferences.
- Prefer narrow capability types over broad `Manager` or `Service` objects.
- Never lose valid text: refiner failure falls back to deterministic text, and insertion failure leaves the final text copyable.
- Production logs must never contain transcript text, audio, clipboard contents, user prompts, or cursor context.

## Licensing

- The intended product is closed-source and directly distributed. Verify code, model-weight, conversion, and transitive licenses before adding dependencies or artifacts.
- OpenLess is AGPLv3 on its active branch; FluidVoice and VoiceInk are GPLv3. Study behavior and public facts only. Do not copy their code, prompts, tests, file layout, or close translations.
- Prefer permissive dependencies such as Apache-2.0 or MIT and retain all required notices.

## Working practice

- Preserve existing user changes and keep each change within the requested scope.
- Update `Spec.md` when product scope changes. Add or supersede an ADR when a durable technical decision changes.
- Add tests with behavior. Do not report performance or quality without measurements from real inputs.
- Follow the verification commands in the nearest scoped guide.

## Near-term sequence

Follow the detailed phases and exit gates in `docs/IMPLEMENTATION_PLAN.md`.

0. Run the standalone model feasibility gate; do not couple it to application code.
1. Add core values, narrow ports, and coordinator state-machine tests.
2. Create the signed menu-bar app and composition root.
3. Build a microphone-to-mock-transcript-to-copy vertical slice.
4. Benchmark ASR candidates on real Chinese, English, French, and mixed audio.
5. Add deterministic processing, insertion fallbacks, local refinement, modes, history, and permission onboarding in that order.
