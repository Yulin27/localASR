#!/usr/bin/env python3
"""Generate a CLAUDE.md mirror beside every AGENTS.md in the repository.

Claude Code loads `CLAUDE.md`, not `AGENTS.md`, and it expands `@path` imports
only for the guide in the working directory, so a pointer file drops the parent
guides from context. A full copy is the only form that loads reliably at every
depth. `AGENTS.md` stays the source of truth; the mirrors are generated.

Usage:
    python3 Scripts/sync_claude_md.py            # regenerate every mirror
    python3 Scripts/sync_claude_md.py --check    # verify mirrors are current

`--check` exits non-zero when a mirror is missing or stale, for use in CI or a
pre-commit hook.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

# Vendored third-party sources ship their own guides; build products are noise.
EXCLUDED_DIR_NAMES = {".build", ".git", ".swiftpm", ".venv", "node_modules"}
EXCLUDED_TOP_LEVEL = {"TestData"}

BANNER = (
    "<!-- Generated from {source} by Scripts/sync_claude_md.py. Do not edit. -->\n"
    "<!-- Claude Code reads CLAUDE.md; AGENTS.md stays the source of truth. -->\n"
    "<!-- After editing {source}, rerun: python3 Scripts/sync_claude_md.py -->\n\n"
)


def guide_paths() -> list[Path]:
    """Return every tracked AGENTS.md, repository order, root first."""
    found = []
    for path in REPO_ROOT.rglob("AGENTS.md"):
        relative = path.relative_to(REPO_ROOT)
        if EXCLUDED_DIR_NAMES.intersection(relative.parts):
            continue
        if relative.parts[0] in EXCLUDED_TOP_LEVEL:
            continue
        if inside_nested_checkout(path):
            continue
        found.append(path)
    return sorted(found, key=lambda p: p.relative_to(REPO_ROOT).as_posix())


def inside_nested_checkout(path: Path) -> bool:
    """Whether `path` belongs to a nested repository or worktree rather than this one.

    A linked worktree checked out below the root, such as `.pi-flow/worktrees/<name>`, has
    its own guides on its own branch. Mirroring them from here would rewrite that branch's
    files with banners naming the wrong source.
    """
    directory = path.parent
    while directory != REPO_ROOT:
        if (directory / ".git").exists():
            return True
        directory = directory.parent
    return False


def rendered(source: Path) -> str:
    relative = source.relative_to(REPO_ROOT).as_posix()
    return BANNER.format(source=relative) + source.read_text(encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="report stale or missing mirrors instead of rewriting them",
    )
    args = parser.parse_args()

    sources = guide_paths()
    if not sources:
        print("No AGENTS.md found; nothing to do.", file=sys.stderr)
        return 1

    stale: list[str] = []
    written: list[str] = []

    for source in sources:
        mirror = source.with_name("CLAUDE.md")
        expected = rendered(source)
        current = mirror.read_text(encoding="utf-8") if mirror.exists() else None
        label = mirror.relative_to(REPO_ROOT).as_posix()

        if current == expected:
            continue
        if args.check:
            stale.append(label if current is not None else f"{label} (missing)")
        else:
            mirror.write_text(expected, encoding="utf-8")
            written.append(label)

    if args.check:
        if stale:
            print("Stale CLAUDE.md mirrors:", file=sys.stderr)
            for label in stale:
                print(f"  {label}", file=sys.stderr)
            print(
                "\nRun: python3 Scripts/sync_claude_md.py",
                file=sys.stderr,
            )
            return 1
        print(f"All {len(sources)} CLAUDE.md mirrors are current.")
        return 0

    if written:
        for label in written:
            print(f"updated {label}")
    print(f"{len(sources)} guides mirrored, {len(written)} changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
