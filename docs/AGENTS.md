# Documentation Guide

This directory contains technical architecture and durable engineering documentation. `Spec.md` at the repository root remains the product source of truth.

- Keep `ARCHITECTURE.md` aligned with implemented module boundaries and accepted ADRs.
- Describe current state separately from intended state; do not present placeholders as finished behavior.
- Link to the source of a rule instead of copying large sections between the spec, architecture, and agent guides.
- Use diagrams only when they clarify lifecycle, dependencies, or data flow, and keep them text-renderable when possible.
- Do not paste GPL/AGPL implementation material or proprietary prompts into documentation.
- When changing product scope, update `Spec.md` first; when changing a durable technical choice, add or supersede an ADR.

