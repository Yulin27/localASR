# Phase 2 handoff

- Date: 2026-09-15
- Plan: [`phase-2.md`](phase-2.md)
- State: complete. The manual exit-gate checklist passed on 2026-09-15 (14 of 14 checks); results
  are in [`phase-2.md`](phase-2.md#step-7-documentation-and-exit-gate).

## Commits on `main` (local, not pushed)

| Commit | Content |
|---|---|
| `ee23feb` | Step 1: `AcceptedActions` on `SessionSnapshot`, same-phase refresh in `finalize`, ADR 0005 |
| `d8c7d10` | Step 2: `DictationDemo` target (scripted adapters, `DemoScenarioSelector`, `ManualClock`) |
| `86af17f` | `Scripts/sync_claude_md.py` skips nested checkouts (it had rewritten `.pi-flow/worktrees/T2` banners; reverted) |
| `fa80483` | Step 3: `App/project.yml`, `App/Config/*.xcconfig`, `Scripts/generate_xcodeproj.sh`, ADR 0006 |
| `9cb77be` | Step 4: composition root (`StartupResult`, assemblies, `CompositionRoot`, `AppDelegate`) |
| `3b10519` | Step 5: `AppModel`, `MenuBarPresentation`, tests |
| `6aa28fe` | Step 6: `MenuBarLabel` / `MenuBarContent` views |
| `740109d` | Step 7 (partial): `App/README.md`, `App/AGENTS.md`, `ARCHITECTURE.md` status |
| `1d34c68` | Step 7: exit-gate results, Phase 2 marked complete |

Each step commit was built and tested on its own in a temporary worktree.

## Verified automatically

- `swift test --package-path Packages/LocalASRKit`: 162 tests pass (Xcode 16.4 toolchain).
- `xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR test`: 23 tests pass.
- Debug and Release build, signed with an Apple Development identity and the locally configured
  team, hardened runtime, `codesign --verify --strict` passes, `LSUIElement = true`.
- Both configurations launch as `ApplicationType = UIElement` (no Dock icon) and exit after an
  AppleScript `quit`, which goes through `applicationShouldTerminate` → `model.shutdown()`.

## Manual exit-gate checklist (passed 2026-09-15)

Debug app: `.build/xcode/Build/Products/Debug/LocalASR.app`
Release app: `.build/xcode/Build/Products/Release/LocalASR.app`
Rebuild first if needed: `Scripts/generate_xcodeproj.sh` then
`xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR -configuration Debug -derivedDataPath .build/xcode build`
(the same with `-configuration Release`).

- [x] Each demo scenario runs Start → Stop → its expected terminal state from the menu.
- [x] Cancel during Recording and during Transcribing shows Cancelled, with no later phase.
- [x] Dismiss returns to Ready; Start from a finished state begins a new session.
- [x] Quitting mid-session exits cleanly.
- [x] The menu refreshes while open as snapshots arrive.
- [x] Opening and closing the menu while typing in TextEdit does not change the frontmost app.
- [x] Release build shows "Dictation Unavailable" and only Quit.
- [x] No feature view constructs a dependency (reviewed: `App/Features/MenuBar` only reads the
      model and calls `send` / `selectDemoScenario`).

Measured results are in [`phase-2.md`](phase-2.md#step-7-documentation-and-exit-gate).

## Automating the checks: what was learned

Resolved: `.build/checks/axctl` (a small Swift tool calling the AX API directly) is trusted from
the Claude Code session, unlike `osascript` via System Events. `.build/checks/phase2-exit-gate.sh`
drives the checklist with it. Findings: presses are reflected about 1–2 s later through the
harness; Accessibility reads while the menu is open can close it after a few seconds; this
terminal has no Screen Recording, so menu pixels cannot be captured.

Earlier notes:

UI scripting through System Events fails with `osascript is not allowed assistive access (-1719)`
from the Claude Code session, even after granting Accessibility to both iTerm2 and
`~/.local/share/claude/ClaudeCode.app`. Disabling the tool sandbox made no difference.

The session's process chain is:

```text
zsh → ~/.local/share/claude/versions/2.1.272 → ClaudeCode.app/Contents/MacOS/claude
    → ~/.local/bin/claude (symlink to versions/2.1.272), parent launchd
```

The session is not a child of iTerm2, and the top-level process is the bare versioned binary,
which is the likely TCC responsible process. Options not yet tried:

1. Grant Accessibility to `~/.local/share/claude/versions/2.1.272` and restart the session. The
   path is version-specific, so the grant probably breaks on the next Claude Code update.
2. Start the new session from an iTerm2 tab that has Accessibility access, and confirm with
   `p=$$; while [ "$p" -gt 1 ]; do ps -o pid=,ppid=,comm= -p $p; p=$(ps -o ppid= -p $p | tr -d ' '); done`
   that iTerm2 is an ancestor. A quick probe:
   `osascript -e 'tell application "System Events" to tell process "LocalASR" to get name of every menu bar item of menu bar 2'`
3. Write a check script into `.build/` and have the user run it in a normal iTerm2 tab.
4. Run the checklist by hand.

Remove the Accessibility grants afterwards if they are no longer wanted.

## After the checklist passed

- Phase 2 is marked complete in `docs/IMPLEMENTATION_PLAN.md` (commit `1d34c68`).
- `docs/phase1-explained.html` has unrelated uncommitted user changes; leave it alone.

## Environment facts

- Xcode 16.4 at `/Applications/Xcode.app` (selected with `xcode-select`), Swift 6.1.2, macOS 15.5.
- XcodeGen 2.46.0 via Homebrew.
- `App/Config/Local.xcconfig` (ignored) sets `DEVELOPMENT_TEAM` to the personal team
  from Xcode's account settings.
- `security find-identity -v -p codesigning` reports 0 valid identities even though signing works
  and `security verify-cert` succeeds. Harmless.
- Decisions that differ from the plan's wording:
  - The demo scenario is read at `AudioCapturing.start()` and carried on the clip, then bound to
    the session ID at recognition, because capture and voice activity receive no session ID.
  - `StartupResult.ready` carries `ReadyServices` (coordinator plus optional demo selector) rather
    than an `AppModel`; the composition root always wraps the result in an `AppModel` so the menu
    can present the not-ready state.
  - The demo picker is shown when `AppModel.demoScenario != nil`, not behind `#if DEBUG` in the
    view; only `CompositionRoot` reads the build configuration.
  - Step 3 added `ApplicationBundleTests` (bundle ID and `LSUIElement`).
- A Debug `LocalASR` process may still be running from the last session; quit it from its menu
  or with `pkill -x LocalASR`.
