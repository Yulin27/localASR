<!-- Generated from Packages/LocalASRKit/Sources/SpeechEngines/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Packages/LocalASRKit/Sources/SpeechEngines/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# SpeechEngines Guide

This module contains local ASR adapters implementing core speech-recognition ports.

## Structure and behavior

- Give each runtime/provider its own subfolder and adapter. Shared mapping code must remain provider-neutral.
- Convert provider outputs into core transcript values at the boundary. Do not expose tensors, SDK result objects, or provider configuration outside this module.
- Separate model preparation from transcription. Starting a recording must not trigger an unexpected model download.
- One final batch transcription is the v0.1 contract. A provider may chunk long audio internally, but it must preserve order and return one coherent final transcript.
- Language hints are hints, not permission to translate. Preserve the spoken language unless the product mode explicitly requests otherwise.
- Make cancellation real: stop inference where supported and reject late completion through session scoping.
- ASR output is raw transcription. Do not remove filler words, rewrite style, or call an LLM here.

## Selection and evaluation

- Do not add a provider merely because an implementation exists. Record license, artifact size, model revision, supported hardware, peak memory, latency, and multilingual quality.
- Keep v0.1 provider choice in composition/configuration, not a user-facing model picker.
- Benchmark Chinese, English, French, code-switching, technical terms, silence, and long dictation on target Mac classes before making a provider the default.

