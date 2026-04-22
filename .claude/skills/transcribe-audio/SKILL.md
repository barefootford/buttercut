---
name: transcribe-audio
description: Transcribes video audio using WhisperX, preserving original timestamps. Creates JSON transcript with word-level timing. Use when you need to generate audio transcripts for videos.
---

# Skill: Transcribe Audio

Transcribes video audio using WhisperX and creates clean JSON transcripts with word-level timing data.

## When to Use
- Videos need audio transcripts before visual analysis

## Critical Requirements

Use WhisperX, NOT standard Whisper. WhisperX preserves the original video timeline including leading silence, ensuring transcripts match actual video timestamps. Run WhisperX directly on video files. Don't extract audio separately - this ensures timestamp alignment.

## Workflow

### 1. Inputs from the parent

This skill runs as a sub-agent. Do NOT read `library.yaml` or `settings.yaml` — the parent has that context and passes everything inline in your prompt. Expect these inputs:

- `video_path` — absolute path to the video file
- `transcript_output_dir` — where to write the transcript JSON (e.g. `libraries/<library>/transcripts`)
- `language_code` — ISO 639-1 code already mapped by the parent (e.g. `en`, `es`)
- `whisper_model` — model size from the parent (e.g. `small`, `medium`, `turbo`)
- `transcript_refinement` — boolean; if `true`, the parent will also pass `user_context` and `footage_summary` strings for Step 4
- `user_context` (only when refinement is on) — may be empty string
- `footage_summary` (only when refinement is on) — may be empty string

If any required input is missing from your prompt, stop and ask the parent rather than inferring it from the filesystem.

### 2. Run WhisperX

```bash
whisperx "<video_path>" \
  --language <language_code> \
  --model <whisper_model> \
  --compute_type float32 \
  --device cpu \
  --output_format json \
  --output_dir <transcript_output_dir>
```

### 3. Prepare Audio Transcript

After WhisperX completes, format the JSON using our prepare_audio_script:

```bash
ruby .claude/skills/transcribe-audio/prepare_audio_script.rb \
  <transcript_output_dir>/<video_basename>.json \
  <video_path>
```

This script:
- Adds video source path as metadata
- Removes unnecessary fields to reduce file size
- Prettifies JSON

### 4. (Optional) Refine the transcript

If the parent passed `transcript_refinement: true`, follow `.claude/skills/transcribe-audio/refine_instructions.md` using the `user_context` and `footage_summary` strings the parent supplied inline. Do NOT open `library.yaml`. If `transcript_refinement` is not set or is `false`, skip this step.

### 5. Return Success Response

After audio preparation completes, return this structured response to the parent agent:

```
✓ <video_basename.mov> transcribed successfully
  Audio transcript: <transcript_output_dir>/<video_basename>.json
  Video path: <video_path>
```

**DO NOT update library.yaml** - the parent agent will handle this to avoid race conditions when running multiple transcriptions in parallel.

## Running in Parallel

This skill is designed to run inside a Task agent for parallel execution:
- Each agent handles ONE video file
- Multiple agents can run simultaneously
- Parent thread updates library.yaml sequentially after each agent completes
- No race conditions on shared YAML file

## Next Step

After audio transcription, use the **analyze-video** skill to add visual descriptions and create the visual transcript.

## Installation

Ensure WhisperX is installed. Use the **setup** skill to verify dependencies.
