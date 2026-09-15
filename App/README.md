# Application shell

This directory contains the signed SwiftUI/AppKit menu-bar application. It depends on the local
`LocalASRKit` package and acts as the composition root.

Feature folders contain presentation code only. Domain workflow and infrastructure implementations
belong in their package modules.

## Layout

- `project.yml`: the XcodeGen specification. The generated `LocalASR.xcodeproj` is not checked in.
- `Config/`: signing settings. `Local.xcconfig` holds your team and is ignored.
- `Application/`: `@main`, the app delegate, and `AppModel`.
- `Composition/`: the assemblies and the composition root that selects one.
- `Features/`: presentation code per feature. Phase 2 has `MenuBar` only.
- `Tests/LocalASRTests/`: unit tests hosted by the application, using Swift Testing.

## Assemblies

| Launch | Assembly | Result |
|---|---|---|
| Debug | `DemoAssembly` | A real coordinator over `DictationDemo` adapters, with a demo scenario picker in the menu. |
| Release | `ProductionAssembly` | Not ready: the menu reports that dictation is unavailable until real adapters exist. |
| Test host | `TestAssembly` | Demo adapters on a manual clock, so the host sits idle. |

## First-time setup

See ADR 0006 for why each step exists.

1. Install Xcode 16.4, select it with `sudo xcode-select -s /Applications/Xcode-16.4.app`, launch it
   once, and accept the license.
2. In Xcode → Settings → Accounts, add your Apple ID and create an Apple Development certificate.
3. `brew install xcodegen`.
4. `cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`.

## Build and test

From the repository root:

```sh
Scripts/generate_xcodeproj.sh
xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR -configuration Debug build
xcodebuild -project App/LocalASR.xcodeproj -scheme LocalASR test
```

Regenerate the project after adding or removing a source file.
