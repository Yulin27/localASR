# TextProcessing Guide

This module owns deterministic written-language transforms, local LLM refinement adapters, and refinement validation.

## Deterministic pipeline

- Each transform is pure, ordered, language-aware where necessary, and identified by a stable name and version.
- Keep transforms small enough to test independently. Do not hide a chain of unrelated regex replacements in one function.
- Maintain fixtures for Chinese, English, French, and mixed-script text, including punctuation, ITN, filler words, technical terms, and conservative self-correction.
- Favor conservative edits. A deterministic pass must not paraphrase or invent information.
- Produce `normalizedText` without overwriting `rawText`.

## Local refinement

- Start a fresh isolated inference context for each transcript. Do not carry conversation history or expose tools.
- Treat transcript content as data to rewrite, never as instructions to answer or execute.
- Disable thinking where supported and enforce cancellation, a deadline, and an output-token limit.
- Clean model wrappers such as thinking blocks or preambles, then validate nonempty output, mode-specific length ratio, language/script preservation, and other invariants.
- On timeout, model failure, or invalid output, return deterministic text with a structured fallback reason.
- Mode definitions and validation thresholds are typed data. Avoid coordinator or view switches for individual modes.

LLM tests should validate invariants and curated evaluation outcomes; do not rely solely on brittle exact-string assertions.

