# ADR 0006: Application shell build and signing

- Status: Accepted
- Date: 2026-09-15

## Context

Phase 2 creates the first application target. Four choices made now are hard to change later,
because each is baked into state that outlives a build: the project file format that every later
source change touches, the signing identity that macOS privacy grants are keyed to, the bundle
identifier that keys those grants and the preferences domain, and whether the app runs in App
Sandbox.

The development Mac runs macOS 15.5. Xcode 26 requires macOS 15.6 or later; Xcode 16.4 runs on
15.5 and ships Swift 6.1.2, the same compiler the package already builds with.

Phases 3 and 7 request microphone and Accessibility permission. macOS records those grants (TCC)
against the application's designated requirement. An ad-hoc signature changes that requirement on
every build, so each rebuild would silently lose both grants and the permission flow could never be
tested repeatably.

## Decision

### 1. The Xcode project is generated from a checked-in XcodeGen specification

`App/project.yml` is the source of truth. `Scripts/generate_xcodeproj.sh` generates
`App/LocalASR.xcodeproj`, which is ignored by git. XcodeGen is MIT-licensed and used at development
time only; nothing from it ships in the product.

The project targets Xcode 16.4, macOS 15.0 deployment, Swift 6 language mode with complete
concurrency checking, and links the local `LocalASRKit` package's `LocalASRKit` and
`DictationDemo` products. The unit-test target `LocalASRTests` is hosted by the application and
uses Swift Testing.

### 2. Local builds are signed with an Apple Development identity

Signing settings live in `App/Config/Signing.xcconfig`: automatic signing, the `Apple Development`
identity, and a team read from `App/Config/Local.xcconfig`, which is ignored. A committed
`Local.xcconfig.example` documents the one value a developer supplies. A personal team is enough;
no paid membership is needed for local development.

Developer ID signing and notarization wait for direct distribution (v0.3). They change the
certificate, not this structure.

### 3. The bundle identifier is `io.github.yulin27.LocalASR`

It is fixed before any permission is requested or any preference is written, because changing it
later orphans both. The test bundle is `io.github.yulin27.LocalASRTests`.

### 4. The application runs with the hardened runtime and without App Sandbox

`Spec.md` requires inserting text into the application that was frontmost when recording began,
through the Accessibility API with a synthetic-paste fallback. A sandboxed application cannot be a
trusted Accessibility client of other applications, and cannot post keyboard events to them. The
product is distributed directly rather than through the Mac App Store, so the sandbox is not a
distribution requirement either.

The hardened runtime is enabled from the start, because notarization will require it and because
it is what makes resource entitlements such as audio input explicit. Phase 3 adds the audio-input
entitlement and the microphone usage description together with capture.

### 5. `LSUIElement` is set

LocalASR is a menu-bar application: it shows no Dock icon and has no main menu of its own.

## Consequences

- A fresh clone needs Xcode 16.4, XcodeGen, an Apple Development certificate, and a
  `Local.xcconfig` before `xcodebuild` works. `App/README.md` lists the steps.
- Adding or removing a source file requires regenerating the project. Editing an existing file
  does not.
- Project changes are reviewed as YAML, and there is no project file to merge.
- Privacy grants survive rebuilds on one machine for one team. A different team produces a
  different designated requirement, and grants must be given again.
- Without the sandbox, the application's file and network access is limited only by the hardened
  runtime and by review. The no-network and local-only invariants in `AGENTS.md` are enforced by
  the code, not by the operating system.
- Moving to Xcode 26 later means a newer macOS on the development machine, a change to
  `xcodeVersion` in the specification, and a check that the package still builds with that
  compiler.

## Alternatives considered

- **A checked-in `.xcodeproj`**: no extra tool, but the project file is merge-hostile and
  unreviewable, and every source addition produces noise in review.
- **Tuist**: more capable, but heavier than one application and one test target need, and it adds
  its own project-description runtime.
- **A SwiftPM executable target as the app**: cannot produce a proper application bundle with an
  Info.plist, entitlements, and hosted unit tests without extra scripting that would reimplement
  what Xcode already does.
- **Ad-hoc signing for local builds**: works without an Apple ID, but invalidates microphone and
  Accessibility grants on every build.
- **App Sandbox with temporary exceptions**: the Accessibility client and event-posting capabilities
  the product needs are not available to sandboxed applications at all.
