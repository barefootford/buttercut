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

### 1. Read Language from Library File

Read the library's `library.yaml` to get the language code:

```yaml
# Library metadata
library_name: [library-name]
language: en  # Language code stored here
...
```

### 2. Run WhisperX

```bash
whisperx "/full/path/to/video.mov" \
  --language en \
  --model medium \
  --compute_type float32 \
  --device cpu \
  --output_format json \
  --output_dir libraries/[library-name]/transcripts
```

### 3. Prepare Audio Transcript

After WhisperX completes, format the JSON using our prepare_audio_script:

```bash
ruby .claude/skills/transcribe-audio/prepare_audio_script.rb \
  libraries/[library-name]/transcripts/video_name.json \
  /full/path/to/original/video_name.mov
```

This script:
- Adds video source path as metadata
- Removes unnecessary fields to reduce file size
- Prettifies JSON

### 4. Return Success Response

After audio preparation completes, return this structured response to the parent agent:

```
✓ [video_filename.mov] transcribed successfully
  Audio transcript: libraries/[library-name]/transcripts/video_name.json
  Video path: /full/path/to/video_filename.mov
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
