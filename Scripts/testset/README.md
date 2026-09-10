# Phase 0 feasibility corpus

Inputs for the Phase 0 model feasibility gate in `docs/IMPLEMENTATION_PLAN.md`.
This is a smoke-test corpus, not the Phase 4 benchmark corpus.

## Contents

- `import_typeless.py` — extracts the local Typeless dictation history into
  16 kHz mono WAV plus a manifest.
- `prompts.md` — sentences to record for the coverage the Typeless history lacks.

## Usage

Prerequisites: Python 3.9+, `ffmpeg` and `ffprobe` on `PATH`.

```
Scripts/testset/import_typeless.py --dry-run   # report, write nothing
Scripts/testset/import_typeless.py             # write TestData/typeless/
```

Output goes to `TestData/`, which is git-ignored. The corpus is personal
dictation audio and must not be committed, uploaded, or sent to a cloud service.

## What the Typeless history provides

Typeless retains the source recording for every history entry, so the extraction
yields real audio and not text alone.

| Property | Value |
| --- | --- |
| Clips | 56 |
| Total audio | ~21 minutes |
| Source format | 48 kHz mono Opus in Ogg |
| Extracted format | 16 kHz mono 16-bit WAV |
| Clips with a transcript result | 33 |
| Clips with no transcript result | 23 |
| Duration range | 0.6 s to 445 s |

Script coverage across the 33 clips that produced text: 14 mixed Han/Latin,
7 Han only, 12 Latin only.

The 23 empty results are short or abandoned presses. They are useful input for
no-speech and very-short-utterance handling rather than dead weight.

The mixed Han/Latin clips are the most valuable part of the set. They are natural
code-switching — Chinese speech carrying English technical terms — which is
exactly the case the spec treats as first-class and which is hard to synthesize.

## Limitations that constrain how this corpus may be used

**The reference text is not a raw ASR transcript.** Typeless stores `refined_text`,
the output of its cloud LLM refinement pass. The pre-refinement transcript lives in
the `debug_info` and `audio_context` columns, both client-side encrypted and not
readable from the local database. Every manifest entry therefore carries
`reference_is_raw_asr: false` and `usable_for_cer_wer: false`.

Consequences:

- Valid for Phase 0: does the model load, run, and return plausible text in the
  spoken language, with acceptable latency and memory.
- Not valid for Phase 4: CER, WER, or any accuracy claim needs human-verified
  transcripts of this audio, or a different corpus.
- The refined text is still a useful target-style reference for Phase 8
  refinement work, since it shows a shipped product's rewrite of the same speech.

**No French.** The history contains zero French dictation. The single French text
is a `voice_translation` output whose audio was spoken in another language, so it
cannot serve as a French ASR input. Phase 0 requires French, so record it —
`prompts.md` covers this gap.

**Lossy source.** The audio was Opus-compressed at 32 kbit/s before storage and is
now transcoded. It represents realistic dictation capture but is not pristine.

**Language labels are heuristic.** `script_label` is computed from the character
classes in the reference text, not from a verified language tag. Treat it as a
sorting aid.

**Single speaker, single microphone.** One voice and one capture device. Nothing
here speaks to speaker or hardware variation.

## Provenance and privacy

The data is the user's own dictation, recorded through their own Typeless
installation and read from local application storage. It contains personal
content including names, phone numbers, and private plans. Keep it local: no
commits, no cloud inference, no sharing. `TestData/` is git-ignored, and the
importer never prints transcript text to stdout.
