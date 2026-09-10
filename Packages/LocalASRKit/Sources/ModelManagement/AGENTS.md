# ModelManagement Guide

This module owns model artifacts independently from ASR and refinement execution.

- Parse a versioned manifest containing stable IDs, upstream revisions, URLs, hashes, quantization, expected files, sizes, licenses, and platform requirements.
- Download into a staging location, verify checksums and expected contents, then promote atomically into the application-support model directory.
- Never download a mutable branch or unpinned latest artifact for a shipped model.
- Model preparation exposes typed phases such as absent, downloading, verifying, compiling, ready, failed, and incompatible.
- Support cancellation, interrupted-download recovery, insufficient disk space, corrupt cache replacement, and model migration.
- Actor-isolate cache mutation and residency decisions. Avoid loading two large runtimes concurrently unless a measured memory policy permits it.
- Keep downloads out of the critical recording path. Onboarding or background preparation must make the selected v0.1 model ready first.
- Do not choose product modes, transcribe audio, refine text, or render download UI here.

Every new artifact requires a license entry and reproducible size/hash evidence in the manifest or accompanying documentation.

