#!/usr/bin/env python3
"""Import the local Typeless dictation history into a Phase 0 feasibility corpus.

Prerequisites: Python 3.9+, ffmpeg and ffprobe on PATH, and a local Typeless
installation that has recorded history.

Usage:
    Scripts/testset/import_typeless.py [--dry-run] [--source PATH] [--out PATH]

The script copies the Typeless SQLite database (the app may be running), decodes
each retained Opus recording to 16 kHz mono 16-bit WAV, and writes a manifest
describing every clip. Audio and manifest land in an ignored output directory.

Transcript text is written to the manifest only. It is never printed to stdout.

Reference-text caveat: Typeless stores `refined_text`, which is the output of its
cloud LLM refinement pass, not a raw ASR transcript. The pre-refinement transcript
is held in `debug_info` and `audio_context`, both client-side encrypted and not
readable here. Treat manifest text as a weak reference suitable for smoke testing
only. It is not a CER/WER ground truth; see Phase 4 in docs/IMPLEMENTATION_PLAN.md.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE = Path.home() / "Library" / "Application Support" / "Typeless"
DEFAULT_OUT = REPO_ROOT / "TestData" / "typeless"

TARGET_SAMPLE_RATE = 16000
TARGET_CHANNELS = 1
MANIFEST_VERSION = 1


def fail(message: str) -> "NoReturn":  # type: ignore[valid-type]
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def display_path(path: Path) -> Path:
    """Return a repo-relative path when possible, otherwise its absolute path."""
    try:
        return path.relative_to(REPO_ROOT)
    except ValueError:
        return path


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        fail(f"{name} not found on PATH. Install it (brew install ffmpeg) and retry.")
    return path


def tool_version(name: str) -> str:
    try:
        out = subprocess.run(
            [name, "-version"], capture_output=True, text=True, check=True
        ).stdout
        return out.splitlines()[0].strip()
    except (subprocess.CalledProcessError, OSError, IndexError):
        return "unknown"


def classify_script(text: str) -> str:
    """Label the dominant writing system. Heuristic, never a verified language tag."""
    if not text:
        return "none"
    han = latin = 0
    for char in text:
        if not char.isalpha():
            continue
        name = unicodedata.name(char, "")
        if name.startswith("CJK"):
            han += 1
        elif name.startswith("LATIN"):
            latin += 1
    if han and latin:
        return "han_latin_mixed"
    if han:
        return "han"
    if latin:
        return "latin"
    return "other"


def probe_duration(ffprobe: str, path: Path) -> float | None:
    result = subprocess.run(
        [
            ffprobe, "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=nokey=1:noprint_wrappers=1",
            str(path),
        ],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None
    try:
        return round(float(result.stdout.strip()), 3)
    except ValueError:
        return None


def decode_to_wav(ffmpeg: str, source: Path, destination: Path) -> bool:
    result = subprocess.run(
        [
            ffmpeg, "-nostdin", "-y", "-loglevel", "error",
            "-i", str(source),
            "-ac", str(TARGET_CHANNELS),
            "-ar", str(TARGET_SAMPLE_RATE),
            "-sample_fmt", "s16",
            str(destination),
        ],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(f"warn: ffmpeg failed for {source.name}", file=sys.stderr)
        return False
    return True


def load_rows(db_path: Path) -> list[dict]:
    """Copy the database before reading; the Typeless app may hold it open."""
    with tempfile.TemporaryDirectory() as tmp:
        snapshot = Path(tmp) / "typeless.db"
        shutil.copy2(db_path, snapshot)
        for suffix in ("-wal", "-shm"):
            sidecar = db_path.with_name(db_path.name + suffix)
            if sidecar.exists():
                shutil.copy2(sidecar, snapshot.with_name(snapshot.name + suffix))

        connection = sqlite3.connect(f"file:{snapshot}?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        try:
            cursor = connection.execute(
                """
                SELECT id, status, mode, refined_text, duration, created_at,
                       audio_local_path, app_version
                FROM history_v2
                ORDER BY created_at
                """
            )
            return [dict(row) for row in cursor.fetchall()]
        finally:
            connection.close()


def build_manifest_entry(
    row: dict, wav_name: str | None, measured_duration: float | None
) -> dict:
    text = (row["refined_text"] or "").strip()
    return {
        "id": row["id"],
        "audio": wav_name,
        "recorded_at": row["created_at"],
        "source_app_version": row["app_version"],
        "typeless_mode": row["mode"],
        "typeless_status": row["status"],
        "reported_duration_seconds": row["duration"],
        "measured_duration_seconds": measured_duration,
        "has_speech_result": bool(text),
        "script_label": classify_script(text),
        "script_label_source": "heuristic_unverified",
        "reference_text": text,
        "reference_text_kind": "typeless_cloud_refined",
        "reference_is_raw_asr": False,
        "usable_for_cer_wer": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                        help="Typeless application support directory")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help="output corpus directory (ignored by git)")
    parser.add_argument("--dry-run", action="store_true",
                        help="report what would be extracted without writing files")
    args = parser.parse_args()

    source: Path = args.source.expanduser()
    # Resolved, so a relative `--out` is still an absolute path by the time the manifest is
    # written and reported.
    out: Path = args.out.expanduser().resolve()

    db_path = source / "typeless.db"
    recordings_dir = source / "Recordings"
    if not db_path.is_file():
        fail(f"no Typeless database at {db_path}")
    if not recordings_dir.is_dir():
        fail(f"no Typeless recordings directory at {recordings_dir}")

    ffmpeg = require_tool("ffmpeg")
    ffprobe = require_tool("ffprobe")

    rows = load_rows(db_path)
    audio_out = out / "audio"
    if not args.dry_run:
        audio_out.mkdir(parents=True, exist_ok=True)

    entries: list[dict] = []
    missing_audio = 0
    decode_failures = 0

    for row in rows:
        local_path = row["audio_local_path"]
        clip = Path(local_path) if local_path else recordings_dir / f"{row['id']}.ogg"
        if not clip.is_file():
            missing_audio += 1
            entries.append(build_manifest_entry(row, None, None))
            continue

        measured = probe_duration(ffprobe, clip)
        wav_name = f"{row['id']}.wav"

        if not args.dry_run:
            if not decode_to_wav(ffmpeg, clip, audio_out / wav_name):
                decode_failures += 1
                entries.append(build_manifest_entry(row, None, measured))
                continue

        entries.append(build_manifest_entry(row, wav_name, measured))

    with_audio = [e for e in entries if e["audio"]]
    total_seconds = sum(e["measured_duration_seconds"] or 0.0 for e in with_audio)

    script_counts: dict[str, int] = {}
    for entry in with_audio:
        script_counts[entry["script_label"]] = script_counts.get(entry["script_label"], 0) + 1

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "provenance": {
            "source": "Typeless macOS dictation history (local, user-owned)",
            "source_database": str(db_path),
            "ffmpeg": tool_version(ffmpeg),
            "ffprobe": tool_version(ffprobe),
        },
        "audio_format": {
            "container": "wav",
            "encoding": "pcm_s16le",
            "sample_rate_hz": TARGET_SAMPLE_RATE,
            "channels": TARGET_CHANNELS,
            "note": "Transcoded from 48 kHz Opus. Lossy source; not pristine audio.",
        },
        "limitations": [
            "reference_text is Typeless cloud LLM output, not a raw ASR transcript",
            "no verified language tags; script_label is a heuristic over the text",
            "unsuitable for CER/WER claims without human-verified transcription",
            "contains the user's personal dictation; keep out of source control",
        ],
        "summary": {
            "rows_in_history": len(entries),
            "clips_with_audio": len(with_audio),
            "clips_missing_audio": missing_audio,
            "decode_failures": decode_failures,
            "total_audio_seconds": round(total_seconds, 1),
            "clips_with_speech_result": sum(1 for e in with_audio if e["has_speech_result"]),
            "clips_without_speech_result": sum(1 for e in with_audio if not e["has_speech_result"]),
            "script_label_counts": script_counts,
        },
        "clips": entries,
    }

    if args.dry_run:
        print(json.dumps(manifest["summary"], indent=2, ensure_ascii=False))
        print("dry run: no files written")
        return 0

    manifest_path = out / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(json.dumps(manifest["summary"], indent=2, ensure_ascii=False))
    print(f"wrote manifest: {display_path(manifest_path)}")
    print(f"wrote audio:    {display_path(audio_out)}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
