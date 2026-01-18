---
name: transcribe-audio
description: Transcribes video audio using WhisperX, preserving original timestamps. Creates JSON transcript with word-level timing. Use when you need to generate audio transcripts for videos.
---

# Skill: Transcribe Audio

Transcribes video audio using WhisperX and creates clean JSON transcripts with word-level timing data. Includes optional LLM refinement to correct domain-specific terminology.

## When to Use
- Videos need audio transcripts before visual analysis

## Critical Requirements

Use WhisperX, NOT standard Whisper. WhisperX preserves the original video timeline including leading silence, ensuring transcripts match actual video timestamps. Run WhisperX directly on video files. Don't extract audio separately - this ensures timestamp alignment.

## Workflow

### 1. Read Context from Library File

Read the library's `library.yaml` to get:
- `language` - language code for WhisperX
- `footage_summary` - description of footage content
- `user_context` - user-provided context (names, terminology, etc.)

```yaml
# Library metadata
library_name: [library-name]
language: en
user_context: "The presenter is Andrew Ford. He mentions TubeSalt (his SaaS product) and ButterCut (his video editing tool)."
footage_summary: "Tutorial videos about Ruby programming and video editing workflows."
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

### 4. Refine Transcript (if context available)

WhisperX transcribes without domain knowledge, so specialized terminology often gets mangled (names, brands, technical jargon). If `footage_summary` or `user_context` contain useful context, refine the transcript using Haiku.

**Skip this step if:**
- `footage_summary` is "No footage analyzed yet." AND `user_context` is empty
- Both fields lack domain-specific terms to guide corrections

**To refine:**

1. Read the transcript JSON file
2. Use the Task tool with `model: "haiku"` to identify corrections:

```
You are reviewing an audio transcript from video footage for transcription errors.

CONTEXT:
{footage_summary}
{user_context}

Your task is to identify transcription errors caused by the speech-to-text model not understanding the subject matter.

Common issues to find:
- Proper nouns (people, companies, products, places)
- Subject-specific terminology and jargon
- Acronyms and abbreviations spoken aloud
- Names that sound like common words

Return a JSON array of proposed corrections. Each correction should have:
- "original": the incorrectly transcribed word/phrase
- "corrected": what it should be
- "reason": brief explanation (e.g., "product name", "person's name", "technical term")

Example output:
[
  {"original": "tube salt", "corrected": "TubeSalt", "reason": "product name"},
  {"original": "butter cut", "corrected": "ButterCut", "reason": "product name"},
  {"original": "Andrew forward", "corrected": "Andrew Ford", "reason": "person's name"}
]

If no corrections are needed, return an empty array: []

Here is the transcript JSON to review:
{transcript_json}
```

3. Present corrections to user for approval:

```
Proposed transcript corrections for [video_filename.mov]:

  "tube salt" → "TubeSalt" (product name)
  "butter cut" → "ButterCut" (product name)
  "Andrew forward" → "Andrew Ford" (person's name)

Apply these corrections?
```

4. If user approves, apply corrections to the transcript JSON and save
5. If user rejects or modifies, handle accordingly

### 5. Return Success Response

After transcription (and refinement if applicable) completes, return this structured response to the parent agent:

```
✓ [video_filename.mov] transcribed successfully
  Audio transcript: libraries/[library-name]/transcripts/video_name.json
  Video path: /full/path/to/video_filename.mov
  Refined: yes/no
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
