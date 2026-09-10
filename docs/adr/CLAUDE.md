<!-- Generated from docs/adr/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing docs/adr/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# ADR Guide

Architecture Decision Records are append-only records of durable choices.

- Use the next four-digit sequence number and a short kebab-case title.
- Include status, date, context, decision, consequences, and alternatives considered.
- Accepted records are historical documents. Fix factual errors explicitly, but do not rewrite the original decision to hide a change.
- Supersede a decision with a new ADR and link both records.
- Use an ADR for module/dependency direction, runtime/provider commitment, process isolation, model distribution/trust, persistence technology, or a major interaction contract.
- Do not use ADRs for routine refactoring, temporary experiments, or implementation details already governed by a module guide.

