---
name: analyze-video
description: Adds visual descriptions to transcripts by extracting and analyzing video frames with ffmpeg. Creates visual transcript with periodic visual descriptions of the video clip. Use when all files have audio transcripts present (transcript) but don't yet have visual transcripts created (visual_transcript).
---

# Skill: Analyze Video (parent brief)

Adds visual descriptions to a video's audio transcript by extracting JPG frames with ffmpeg and analyzing them.

`SKILL.md` is the parent's dispatch brief. The sub-agent's working prompt lives in `agent_prompt.md` — inline its contents when launching the Task agent. Don't pass `SKILL.md`.

## Prerequisites

Each video must already have an audio transcript. Run `transcribe-audio` first if any are missing.

## Parallelism

Launch at most **8 in parallel**. ffmpeg frame extraction is a brief CPU burst at the start; the rest of the runtime is LLM API calls. 8 is a comfortable middle ground that won't saturate older machines.

## Inputs to gather and pass inline

- `video_path` — absolute path to the video file
- `audio_transcript_path` — absolute path to the prepared audio transcript JSON
- `visual_transcript_path` — absolute path to write the visual transcript JSON

After the agent returns, update `library.yaml` with `visual_transcript: <filename>.json`.

## Next step

Once all videos have visual transcripts, dispatch `summarize-video` (Haiku model) to produce summaries.
