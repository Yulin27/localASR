<!-- Generated from App/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing App/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# Application Shell Guide

This directory contains the macOS application shell. Package implementations belong under `Packages/LocalASRKit`, not here.

## Responsibilities

- Own `@main`, `AppDelegate`, menu-bar lifecycle, windows/panels, app entitlements, resources, and the application-level observable model.
- Render immutable coordinator state and forward user intent to injected use cases.
- Keep all UI-observable mutation on `@MainActor`.
- Import package modules through their public interfaces; do not reach into provider internals.

## Boundaries

- Do not put recording, ASR, refinement, persistence, hotkey, or insertion implementations in a view.
- Do not construct production dependencies inside feature views. Construction belongs in `Composition/`.
- Avoid a catch-all app state object. Feature presentation state may be local, while dictation lifecycle state comes from the coordinator.
- Floating recording UI must not steal key-window status, change the captured destination, or become an unintended Accessibility target.
- Keep menu-bar and overlay rendering useful when no settings window is open.

## Verification

The Xcode project is generated from `App/project.yml` and is not checked in (ADR 0006). Setup prerequisites are in `App/README.md`. Run from the repository root, in addition to the package checks defined in `Packages/LocalASRKit/AGENTS.md`:

```sh
Scripts/generate_xcodeproj.sh
xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR -configuration Debug build
xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR test
```

- Edit `project.yml`, never the generated project. Regenerate after adding or removing source files.
- Build configuration and launch environment are read only in `Composition/CompositionRoot.swift`. Features never branch on `DEBUG` or on which assembly is running.
- The Debug build runs `DictationDemo` adapters; the Release build must report not ready until real adapters exist.

