# Transcribe Audio (sub-agent prompt)

You are a sub-agent. Transcribe one video file using WhisperX and produce a clean JSON transcript with word-level timing.

**Critical:** Use WhisperX, NOT standard Whisper. WhisperX preserves the original video timeline including leading silence, ensuring transcripts match actual video timestamps. Run WhisperX directly on the video file — don't extract audio separately.

## Inputs (passed inline by the parent)

- `video_path` — absolute path to the video file
- `transcript_output_dir` — where to write the transcript JSON
- `language_code` — ISO 639-1 code (e.g. `en`, `es`)
- `whisper_model` — model size (e.g. `small`, `medium`, `turbo`)
- `transcript_refinement` — boolean; if `true`, also expect:
  - `user_context` — string, may be empty
  - `footage_summary` — string, may be empty

Do NOT read `library.yaml` or `settings.yaml`. If a required input is missing from your prompt, stop and ask the parent rather than inferring from the filesystem.

## 1. Run WhisperX

```bash
whisperx "<video_path>" \
  --language <language_code> \
  --model <whisper_model> \
  --compute_type float32 \
  --device cpu \
  --output_format json \
  --output_dir <transcript_output_dir>
```

### Silent / B-roll fallback

If WhisperX exits with `No active speech found in audio`, the clip is B-roll (silent or music-only). This is **not an error** — visuals are the only signal, and `analyze-video` will annotate them later. Probe duration and write a stub transcript:

```bash
DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "<video_path>")
cat > <transcript_output_dir>/<video_basename>.json <<JSON
{"segments": [], "word_segments": [], "language": "<language_code>", "duration": $DUR, "b_roll": true}
JSON
```

Then continue to step 2 as normal. Note `(silent / b-roll)` in your success response.

## 2. Prepare audio transcript

```bash
ruby .claude/skills/transcribe-audio/prepare_audio_script.rb \
  <transcript_output_dir>/<video_basename>.json \
  <video_path>
```

This script adds the video source path as metadata, removes unnecessary fields, and prettifies the JSON.

## 3. (Optional) Refine the transcript

If `transcript_refinement: true`, follow `.claude/skills/transcribe-audio/refine_instructions.md`, using the `user_context` and `footage_summary` strings the parent supplied inline. Do NOT open `library.yaml`. Skip if `transcript_refinement` is missing or `false`.

## 4. Return success response

```
✓ <video_basename.mov> transcribed successfully
  Audio transcript: <transcript_output_dir>/<video_basename>.json
  Video path: <video_path>
```

If the clip was B-roll, append `(silent / b-roll)` to the first line.

**Do NOT update library.yaml** — the parent handles all yaml I/O to avoid race conditions in parallel runs.
