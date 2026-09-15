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

Once the Xcode project exists, build its application scheme and run UI/unit tests in addition to the package checks defined in `Packages/LocalASRKit/AGENTS.md`.

