---
name: transcribe-audio
description: Transcribes video audio using Parakeet MLX, preserving original timestamps. Creates JSON transcript with word-level timing. Use when you need to generate audio transcripts for videos.
---

# Skill: Transcribe Audio (parent brief)

Transcribes video audio using Parakeet MLX and produces a clean JSON transcript with word-level timing, normalized into the same shape ButterCut has always consumed.

`SKILL.md` is the parent's dispatch brief. The sub-agent's working prompt lives in `agent_prompt.md` — inline its contents when launching the Task agent. Don't pass `SKILL.md`.

## Parallelism

Launch at most **2 in parallel**. Parakeet MLX runs on the Apple Neural Engine / GPU via MLX; 2 processes is the throughput-vs-memory sweet spot on a 16GB Mac.

## Inputs to gather and pass inline

The parent reads `library.yaml` and passes these values inline in each agent's prompt:

- `video_path` — absolute path to the video file
- `transcript_output_dir` — where to write the transcript JSON (e.g. `libraries/<library>/transcripts`)
- `language_code` — ISO 639-1 code (e.g. `en`, `es`) — parent maps from library.yaml's `language`
- `transcript_refinement` — boolean from library.yaml. If `true`, also pass:
  - `user_context` (may be empty string)
  - `footage_summary` (may be empty string)

After the agent returns, update `library.yaml` with `transcript: <filename>.json`.

## Next step

Once all videos have audio transcripts, dispatch `analyze-video` for visual descriptions.

## Dependencies

Parakeet MLX must be installed. Use the **setup** skill to verify.
