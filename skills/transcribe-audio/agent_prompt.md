# Transcribe Audio (sub-agent prompt)

You are a sub-agent. Transcribe one video file using Parakeet MLX and produce a clean JSON transcript with word-level timing, normalized to ButterCut's standard transcript shape.

**Critical:** Run Parakeet directly on the video file — don't extract audio separately. Parakeet uses ffmpeg internally and preserves the original video timeline.

## Inputs (passed inline by the parent)

- `video_path` — absolute path to the video file
- `transcript_output_dir` — where to write the transcript JSON
- `language_code` — ISO 639-1 code (e.g. `en`, `es`)
- `transcript_refinement` — boolean; if `true`, also expect:
  - `user_context` — string, may be empty
  - `footage_summary` — string, may be empty

Do NOT read `library.yaml` or `settings.yaml`. If a required input is missing from your prompt, stop and ask the parent rather than inferring from the filesystem.

## 1. Run Parakeet MLX

```bash
parakeet-mlx "<video_path>" \
  --output-format json \
  --output-dir <transcript_output_dir>
```

This writes `<transcript_output_dir>/<video_basename>.json` in Parakeet's native shape (`text`, `sentences[]`, `tokens[]`).

## 2. Normalize to ButterCut's transcript shape

```bash
ruby .claude/skills/transcribe-audio/parakeet_normalizer.rb \
  <transcript_output_dir>/<video_basename>.json \
  <video_path> \
  <language_code>
```

Rewrites the file in place: `sentences` → `segments`, `tokens` → `words`, adds a flat `word_segments` array, plus `language` and `video_path` metadata. Pretty-printed.

## 3. (Optional) Refine the transcript

If `transcript_refinement: true`, follow `.claude/skills/transcribe-audio/refine_instructions.md`, using the `user_context` and `footage_summary` strings the parent supplied inline. Do NOT open `library.yaml`. Skip if `transcript_refinement` is missing or `false`.

## 4. Return success response

```
✓ <video_basename.mov> transcribed successfully
  Audio transcript: <transcript_output_dir>/<video_basename>.json
  Video path: <video_path>
```

**Do NOT update library.yaml** — the parent handles all yaml I/O to avoid race conditions in parallel runs.
