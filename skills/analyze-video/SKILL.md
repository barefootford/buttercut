---
name: analyze-video
description: Adds visual descriptions to transcripts AND writes per-clip markdown summaries from grid montages of video frames. Use when videos have audio transcripts (transcript) but don't yet have visual transcripts (visual_transcript) or summaries (summary).
---

# Skill: Analyze Video (parent brief)

Adds visual descriptions AND per-clip markdown summaries to video transcripts. The parent pre-builds every clip's grid montage and pre-preps its visual transcript JSON, then dispatches batched sub-agents that only do the reasoning work (read grids, write visual descriptions, write summaries).

`SKILL.md` is the parent's dispatch brief. The sub-agent's working prompt lives in `agent_prompt.md` — inline its contents when launching the Task agent. Don't pass `SKILL.md`.

## Prerequisites

Each video must already have an audio transcript. Run `transcribe-audio` first if any are missing.

## Parent workflow

For every dispatch wave, the parent does steps 1–3 **before** launching any sub-agents:

### 1. Pre-bake all grid montages in parallel

Write a tab-separated manifest at `tmp/analyze_dispatch/grids.tsv` with one line per clip in the wave:

```
<video_path>\t<grid_output_path>
```

Use `tmp/frames/<video_name>/grid.jpg` as the `grid_output_path` convention. Then run:

```bash
# Prefer mise if available; fall back to bare ruby otherwise.
mise exec -- ruby .claude/skills/analyze-video/batch_grid_montage.rb tmp/analyze_dispatch/grids.tsv [concurrency]
```

Default concurrency is 8 (≈4.8 GB peak RSS). The script prints one line per clip to stdout:

```
<video_path>\t<grid_path>[,<grid_path>...]
```

Clips ≤10 minutes produce one adaptive grid path; longer clips produce N adaptive grid paths separated by commas. The adaptive layouts are:

- ≤5s: 3×1 (3 tiles)
- ≤10s: 2×2 (4 tiles)
- ≤30s: 3×2 (6 tiles)
- ≤60s: 4×2 (8 tiles)
- ≤2m: 4×3 (12 tiles)
- >2m: 4×4 (16 tiles)

Parse the grid script output — you'll pass the comma-separated grid path(s) inline to the sub-agent.

### 2. Pre-prep all visual transcripts in parallel

Write a tab-separated manifest at `tmp/analyze_dispatch/transcripts.tsv` with one line per clip:

```
<audio_transcript_path>\t<visual_transcript_path>
```

Then run:

```bash
# Prefer mise if available; fall back to bare ruby otherwise.
mise exec -- ruby .claude/skills/analyze-video/batch_prepare_visual_scripts.rb tmp/analyze_dispatch/transcripts.tsv
```

This is pure JSON munging — fast enough to run serially across all clips in one Ruby invocation.

### 3. Dispatch sub-agents

For each batch (10 clips per batch), call the Agent tool with:

- `subagent_type: "analyze-video"` — pinned to Sonnet via `.claude/agents/analyze-video.md`
- `model: "sonnet"` — belt-and-suspenders; the agent definition already pins this, but pass it explicitly so an override mistake takes two failures, not one
- `prompt`: the contents of `agent_prompt.md` followed by the per-clip input list (see "Inputs to pass inline" below)

Run up to **8 sub-agents in parallel** per dispatch wave (≈80 clips). As soon as one batch returns, kick off the next.

## Batching and parallelism

- **Batch size**: 10 clips per sub-agent. The patterns reference and example grids are read once at the start and amortized across the batch.
- **Parallelism cap**: up to **8 sub-agents in parallel**.

## Inputs to pass inline (per clip)

For each clip in the batch, append a numbered entry to the agent prompt's "Clips in this batch" section with:

- `video_filename` — the source video's filename (for display in the summary header and return line)
- `grid_paths` — comma-separated absolute paths to the pre-built grid(s)
- `visual_transcript_path` — absolute path to the pre-prepped visual transcript JSON
- `summary_output_path` — absolute path to write the markdown summary (e.g., `libraries/[library-name]/summaries/summary_[videoname].md`)

The sub-agent does NOT receive `video_path` or `audio_transcript_path` — it never opens the video and never copies the audio transcript.

## Handling returns

The sub-agent returns one line per clip:

```
✓ <video_filename.mov>
✗ <video_filename.mov> → ERROR: <reason>
```

**Trust but verify against disk.** For each clip in the batch, check that BOTH `visual_transcript_path` and `summary_output_path` exist:
- Both exist → update `library.yaml` with `visual_transcript: <filename>.json` AND `summary: <filename>.md`
- Either missing → log the failure and queue that clip for re-dispatch

Write the verified filenames to `library.yaml` immediately after each batch completes, before launching additional batches. This preserves completed work if a later batch fails or the session is interrupted.

If an agent dies mid-batch, completed clips have already written both files to disk. The disk check picks them up; the parent only re-dispatches the un-completed ones.

## Cleanup

After verifying a batch's outputs, the parent removes that batch's `tmp/frames/<video_name>/` directories. After the whole wave finishes, also remove `tmp/analyze_dispatch/`.

## Next step

Once all clips have both visual transcripts and summaries, run the "Confirm footage understanding" pass — see AGENTS.md.
