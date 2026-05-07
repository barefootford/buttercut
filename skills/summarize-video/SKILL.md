---
name: summarize-video
description: Generates a short markdown summary of a video from its visual transcript. Covers overview, key visuals, notable dialogue, and b-roll. Run after analyze-video as the final footage analysis step; summaries become a required field on every video before any roughcut can be created. Always launch this skill using the Haiku model.
---

# Skill: Summarize Video (parent brief)

Generates a short markdown summary from a video's visual transcript. Always launch on the **Haiku model**.

`SKILL.md` is the parent's dispatch brief. The sub-agent's working prompt lives in `agent_prompt.md` — inline its contents when launching the Task agent. Don't pass `SKILL.md`.

## Parallelism

Launch (at most) 10 agents in parallel until all videos are summarized.

## Pre-create the skeleton (parent step, before launching the agent)

For each video, the parent runs:

```bash
ruby .claude/skills/summarize-video/summary_skeleton.rb <visual_transcript_path> <summary_output_path>
```

This writes a skeleton file with the header (filename + duration) filled in and four `<!-- FILL_X -->` placeholders in the body. The agent fills them via `Edit`. The skeleton + Edit pattern is required: without it, Haiku frequently refuses Write and dumps markdown into its reply instead.

## Inputs to gather and pass inline

- `visual_transcript_path` — absolute path to the visual transcript JSON
- `summary_output_path` — absolute path to the pre-created skeleton file

After the agent returns, update `library.yaml` with `summary: <filename>.md`.
