# Composition Guide

This folder is the only production dependency-composition location.

- Construct long-lived actors, repositories, adapters, the coordinator, and the `@MainActor` application model here.
- Make object lifetimes explicit: application, model-residency, and one-session resources are different lifetimes.
- Provide separate production and preview/test assemblies rather than environment conditionals scattered through features.
- Composition may know concrete types from all package modules. Those modules must never depend back on composition or the app.
- Keep feature flags and provider selection here or in injected configuration. Do not place orchestration or business rules here.
- Fail startup with a typed, user-presentable readiness state; do not hide dependency-construction failures with force unwraps.

