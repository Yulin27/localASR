<!-- Generated from Scripts/AGENTS.md by Scripts/sync_claude_md.py. Do not edit. -->
<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->
<!-- After editing Scripts/AGENTS.md, rerun: python3 Scripts/sync_claude_md.py -->

# Scripts Guide

This directory contains repeatable development, benchmark, build, signing, notarization, and release helpers.

- Scripts must be noninteractive where practical, fail clearly, and resolve repository-relative paths from their own location.
- Do not assume the caller's current directory or overwrite common environment variables such as `HOME`.
- Keep destructive targets explicit and validated. Never recursively delete a workspace root, home directory, or unresolved variable.
- Never print API tokens, signing credentials, transcript content, or captured audio paths into shared logs.
- Pin model revisions and verify hashes. A benchmark script must record model revision, machine/OS, settings, warm/cold status, corpus, and units.
- Generated artifacts belong in ignored build/output directories, not beside source files.
- Add a dry-run mode for release or destructive maintenance scripts where useful.
- Document prerequisites and usage at the top of each nontrivial script or in `Scripts/README.md`.

