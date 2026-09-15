# Phase 2 plan: menu-bar application shell

- Status: Complete
- Date: 2026-09-15
- Phase definition and exit gate: [`IMPLEMENTATION_PLAN.md` § Phase 2](../IMPLEMENTATION_PLAN.md#phase-2-menu-bar-application-shell)
- Builds on: [ADR 0001](../adr/0001-modular-monolith.md), [ADR 0003](../adr/0003-core-contracts-and-coordinator.md)

This plan breaks Phase 2 into ordered steps. Each step ends with a check and one commit.
It does not change the phase's scope or exit gate.

## Starting point

- `DictationCore` is complete; `swift test --package-path Packages/LocalASRKit` passes 137 tests.
- The development Mac runs macOS 15.5 with Command Line Tools only (Swift 6.1.2). Full Xcode,
  XcodeGen, and a code-signing identity are all absent, so no app target can be built yet.
- The coordinator's fakes live in `DictationCoreTests` and are not importable by the app.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Xcode | Xcode 16.4 | Runs on macOS 15.5 and ships Swift 6.1.2, matching the package toolchain. Xcode 26 requires macOS 15.6 or later. |
| Project | XcodeGen spec checked in, `.xcodeproj` generated and ignored | Reviewable text instead of a merge-hostile project file. XcodeGen is MIT and a development-time tool only. |
| Signing | Apple Development identity from a personal team | A stable designated requirement keeps microphone and Accessibility grants across rebuilds in Phases 3 and 7. Developer ID waits for notarization (v0.3). |
| Bundle ID | `io.github.yulin27.LocalASR` | It keys TCC grants and preferences, so it is fixed before any permission is requested. |
| Demo adapters | New package target `DictationDemo` | Usable by the app, previews, and app tests; the latch-based test fakes stay test-only. |
| Command availability | The coordinator publishes accepted actions on the snapshot | The coordinator decides from its active session, not the published phase (see step 1), so a view deriving commands from the phase would disagree with it. |
| Assemblies | Debug launches the demo assembly; production reports a typed not-ready state | Fakes can never pose as a working Release build. |
| Demo depth | Selectable scenarios in a Debug-only menu section | Every rendered state can be checked by hand before real adapters exist. |
| UI scope | `MenuBarExtra` in `.menu` style only | The recording overlay waits for Phase 3, when real target capture makes focus behaviour testable. |

Steps 1 and 3 each record their durable decisions in an ADR.

---

## Step 0: Toolchain (manual)

1. Install Xcode 16.4 (Apple Developer downloads, or `xcodes`, MIT).
2. `sudo xcode-select -s /Applications/Xcode-16.4.app` (adjust to the installed name), launch
   it once, and accept the license and component install.
3. Xcode → Settings → Accounts: add an Apple ID and create an Apple Development certificate
   for the personal team.
4. `brew install xcodegen` (MIT, 2.46.0 at time of writing).

**Done when**

- `xcodebuild -version` reports Xcode 16.4.
- `security find-identity -v -p codesigning` lists an `Apple Development` identity.
- `swift test --package-path Packages/LocalASRKit` still passes under the Xcode toolchain.

No commit.

## Step 1: Accepted actions on the snapshot (`DictationCore`)

**Problem.** Acceptance is decided from different state than the snapshot shows:

- `toggleRecording` and `cancel` decide from `active`, the session in flight.
- `dismiss` decides from the published phase.
- `finalize` clears `active` before it awaits device release and the history write, and only
  then publishes the terminal snapshot. During that window the snapshot still reads the last
  processing phase while the coordinator would already start a new session.

**Work**

- Add a public value to `SessionSnapshot` describing what the coordinator accepts right now:
  what `toggleRecording` would do (start, stop, or nothing), whether `cancel` applies, and
  whether `dismiss` applies. The coordinator computes it from its own state when it builds a
  snapshot; views never derive it.
- In `finalize`, when clearing `active` changes the accepted actions of the session still on
  screen, publish a same-phase refresh in that same actor step. The terminal snapshot still
  follows the history write, so the ordering guarantee in ADR 0003 is unchanged.
- Document the one window that stays unpublished by design: a new session's pre-freeze window,
  where nothing may be published (ADR 0003 §5). An action sent then is still decided by the
  coordinator against its real state.

**Tests**

- Accepted actions for every phase, including preparing, recording, each processing phase,
  and each terminal phase.
- The cleanup window: park the history store, and assert that a refresh shows toggle-to-start
  while the phase is unchanged, then that the terminal snapshot follows.
- Cancellation publishes accepted actions consistent with `active == nil`.
- Update the exact phase-sequence assertions in `CoordinatorLifecycleTests` (the happy path and
  the stage-timing test) to account for the refresh explicitly rather than weakening them.

**Docs**

- ADR 0005: accepted actions are published by the coordinator. It amends, and does not
  supersede, ADR 0003 §1 and §4.
- `ARCHITECTURE.md` § Observing the coordinator.

**Done when** the package tests pass and ADR 0005 is accepted. Commit.

## Step 2: `DictationDemo` package target

**Work**

- Add target and library product `DictationDemo`, depending only on `DictationCore`.
- A `DemoScenario` enum: success, refinement fallback, copied-only insertion, recognition
  failure, no speech.
- Scripted adapters for all twelve ports with delays from an injected `Clock`, so the app can
  use `ContinuousClock` and tests a controllable clock. They touch no microphone, pasteboard,
  Accessibility API, network, or model.
- A scenario selector that fixes the scenario per session ID at first lookup, so changing the
  selection mid-session affects the next session only.
- A factory returning `DictationCoordinator.Dependencies` for a scenario selector and clock.

**Tests** (`DictationDemoTests`)

- Each scenario drives a real `DictationCoordinator` to its expected terminal snapshot.
- Changing the scenario mid-session does not alter the session in flight.

**Housekeeping**

- `Package.swift`, the dependency graph in `Packages/LocalASRKit/AGENTS.md` (then
  `python3 Scripts/sync_claude_md.py`), and the module marker in `ArchitectureTests`.

**Done when** the package builds and tests pass with the new target. Commit.

## Step 3: Application project and signing

**Work**

- `App/project.yml` defining:
  - app target `LocalASR`: macOS 15.0 deployment target, bundle ID
    `io.github.yulin27.LocalASR`, `LSUIElement = YES`, Swift 6 language mode with complete
    concurrency checking, linking the local `LocalASRKit` and `DictationDemo` products;
  - unit-test target `LocalASRTests` hosted by the app, using Swift Testing;
  - Debug and Release configurations.
- Signing through a checked-in `App/Config/Signing.xcconfig` that includes an ignored
  `App/Config/Local.xcconfig` holding `DEVELOPMENT_TEAM`, with a committed example file.
- `Scripts/generate_xcodeproj.sh`: resolves paths from its own location, fails clearly when
  XcodeGen is missing, and generates `App/LocalASR.xcodeproj`.
- `.gitignore`: the generated project and `Local.xcconfig`.
- Minimal `@main` app and `AppDelegate` with an empty status item, enough to launch.

**Docs**

- ADR 0006: application shell build and signing — XcodeGen, Apple Development signing for
  local builds, the bundle ID, and running without App Sandbox, because Accessibility insertion
  and synthetic paste require it in a directly distributed app.

**Done when**

- `xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR -configuration Debug build`
  succeeds.
- The app launches with a status item and no Dock icon.
- `codesign -dv --verbose=2` on the built app shows an `Apple Development` authority, not
  ad-hoc.

Commit.

## Step 4: Composition root

**Work** (`App/Composition/`)

- A typed startup result: ready with an application model, or not ready with a
  user-presentable issue.
- `ProductionAssembly`: returns not ready with `adaptersUnavailable` until Phase 3 supplies
  real adapters. No force unwraps.
- `DemoAssembly` (Debug): a coordinator over `DictationDemo` adapters with `ContinuousClock`
  and a scenario selector.
- `TestAssembly`: demo adapters on a controllable clock for `LocalASRTests`.
- Selection happens once, in the composition root: the test assembly when hosted by tests,
  otherwise demo in Debug and production in Release. No conditionals in features.
- Explicit lifetimes: the coordinator and model live for the application. The app delegate
  calls `shutdown()` on termination.

**Tests**

- The production assembly reports not ready.
- The demo assembly yields a coordinator in `.idle`.
- Termination shuts the coordinator down.

**Done when** Debug launches ready and Release launches not ready. Commit.

## Step 5: Application model and menu presentation

**Work**

- `AppModel`, `@MainActor` and `@Observable`: holds the startup result and the latest snapshot,
  consumes `snapshots()` in a task it owns, and forwards `DictationAction`s to
  `coordinator.handle(_:)`. It holds no workflow state of its own.
- `MenuBarPresentation`, a pure value built from a snapshot: status text, SF Symbol,
  accessibility label, and the command list taken directly from the snapshot's accepted
  actions. It shows phase, failure category, and fallback outcome only; no transcript text in
  Phase 2.

**Tests**

- Presentation for every phase, every failure category, and a representative fallback.
- The model reflects streamed snapshots and forwards each action.
- The observation task ends when the coordinator shuts down.

**Done when** `xcodebuild test -scheme LocalASR` passes. Commit.

## Step 6: `MenuBar` feature

**Work** (`App/Features/MenuBar/`)

- `MenuBarExtra` with `.menuBarExtraStyle(.menu)`; the label icon follows the presentation.
- Contents: status line, the toggle command titled Start or Stop, Cancel, Dismiss, then Quit.
  A Debug-only "Demo scenario" picker sits between them.
- Not-ready state: status line naming the issue, and Quit.
- Accessibility labels for the status-only icon and every command.
- Views receive the model and send actions; they construct nothing.

**Checks**

- The menu refreshes while it is open as snapshots arrive. This is an unverified assumption
  about `.menu`-style content; if it fails, record the finding before choosing a workaround.
- Opening and closing the menu while typing in TextEdit does not change the frontmost
  application.

**Done when** every scenario plays from the menu. Commit.

## Step 7: Documentation and exit gate

**Docs**

- `ARCHITECTURE.md` status: the app shell exists, running demo adapters.
- `App/README.md` and `App/AGENTS.md` verification commands (then run the sync script).
- `IMPLEMENTATION_PLAN.md`: Phase 2 status.

**Automated**

```sh
swift build --package-path Packages/LocalASRKit
swift test --package-path Packages/LocalASRKit
Scripts/generate_xcodeproj.sh
xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR test
```

**Manual exit-gate checklist** (record results in the commit or PR)

- [x] Debug build launches as a menu-bar app with no Dock icon.
- [x] Each demo scenario runs start → stop → terminal state from the menu.
- [x] Cancel during recording and during processing returns a cancelled state immediately.
- [x] Dismiss returns to idle; Start from a terminal state begins a new session.
- [x] Quitting mid-session exits cleanly.
- [x] Release build shows the not-ready state.
- [x] No feature view constructs a dependency (reviewed: `App/Features/MenuBar` only reads the
      model and calls `send` / `selectDemoScenario`).

Results (2026-09-15, commit `740109d`, driven through the Accessibility API):

- Launch: `ApplicationType = UIElement`.
- Scenarios: Success → Inserted; Refinement Fallback → Inserted with "Refinement timed out;
  kept the cleaned-up text."; Copied Only → Copied to Clipboard; Recognition Failure →
  Processing Failed; No Speech → No Speech Detected.
- Cancel: Cancelled appeared 2.17 s after the press during Recording, and 2.16 s after the
  press during Transcribing, with no later phase. Start → Recording took 2.22 s through the
  same harness against 0.42 s of scripted delay, so the delay is the harness, not the
  coordinator, which publishes `.cancelled` synchronously.
- Dismiss returned to Ready; Start after Inserted reached Recording.
- Quit during Recording: the process exited within 0.2 s, with no crash report.
- While typing in TextEdit, TextEdit stayed frontmost before, during, and after the menu
  was open, and the typed text was intact.
- Release: "Dictation Unavailable", its detail line, and Quit LocalASR only.

Commit.

## Risks

- **Menu refresh while open** (step 6): verified. With the menu held open, its rows went
  Transcribing… → Refining… → Inserting… → Inserted. Read through Accessibility, not from
  pixels, and the menu window stayed on screen throughout.
- **Pre-freeze window**: the snapshot's accepted actions describe the previous session for the
  short time before a new session freezes its context. The coordinator still decides correctly;
  only a command label can be momentarily stale.
- **Same-phase refresh** adds an observable snapshot that later subscribers such as
  `RecordingOverlay` must tolerate.

## Out of scope

Global shortcut, real target capture, recording overlay, settings, history, onboarding,
microphone or Accessibility permissions, and any real adapter. These belong to Phase 3 and later.
