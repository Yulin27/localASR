# Scripts

Test corpora for the Phase 0 feasibility gate live in `testset/`.

Place repeatable model benchmarks, app build checks, signing, notarization, and release helpers here. Scripts must not download mutable model revisions without checksum verification.

`sync_claude_md.py` mirrors every `AGENTS.md` to a generated `CLAUDE.md` beside it.
Run it after editing a guide; `--check` fails when a mirror is stale.
