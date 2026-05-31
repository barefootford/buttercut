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

## 1. Transcribe (WhisperX + prepare)

One command runs WhisperX and prepares the JSON (adds the video source path, drops unneeded fields, prettifies it):

```bash
ruby lib/buttercut/transcribe_job.rb <video_path> <transcript_output_dir> <language_code> <whisper_model>
```

This is the single source of truth for the transcription command — don't hand-write a raw `whisperx` invocation.

## 2. (Optional) Refine the transcript

If `transcript_refinement: true`, follow `skills/transcribe-audio/refine_instructions.md`, using the `user_context` and `footage_summary` strings the parent supplied inline. Do NOT open `library.yaml`. Skip if `transcript_refinement` is missing or `false`.

## 3. Return success response

```
✓ <video_basename.mov> transcribed successfully
  Audio transcript: <transcript_output_dir>/<video_basename>.json
  Video path: <video_path>
```

**Do NOT update library.yaml** — the parent handles all yaml I/O to avoid race conditions in parallel runs.
