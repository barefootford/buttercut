---
name: analyze-video
description: Full footage analysis pipeline — audio transcripts, contact sheets, clean scripts, and Sonnet-written summaries. Produces every artifact the roughcut skill reads. Orchestrated from the main thread.
---

# Skill: Analyze Video (parent brief)

This is the main thread's playbook for the **Analyze Video** workflow step. Run it after library setup, before any roughcut. It covers all four artifacts produced per clip: audio `transcript`, `contact_sheet`, clean `script`, and markdown `summary`.

`SKILL.md` is the parent's dispatch brief. The sub-agent working prompt lives in `agent_prompt.md` — inline its contents when launching a Task agent. Don't pass `SKILL.md`.

## Terminology

- **User-facing:** call it "footage analysis" or "analyzing footage."
- **Internal/file names:** "transcription" (library.yaml field `transcript`, etc.).

## Prerequisites

- Library setup is complete (`library.yaml` exists, schema is current — run migrations from AGENTS.md if not).
- Read `libraries/settings.yaml` directly for `whisper_model`. For library fields, use `Library.find(name)` and the readers `.language`, `.transcript_refinement`, `.user_context`, `.footage_summary`, `.editor` — don't parse library.yaml inline.

## Step 1 — Audio transcripts (parallel sub-agents)

Inform the user: "Library setup complete. Found [N] videos ([total size]). Starting footage analysis..."

Launch `transcribe-audio` Task agents. Pass these values **inline** in each agent's prompt:

- `video_path`, `transcript_output_dir`, `language_code`, `whisper_model`
- `transcript_refinement` (boolean). If `true`, also pass the current `user_context` and `footage_summary` strings (empty strings are fine — refinement still catches nonsense-token and self-witness fixes).

As each agent completes, update library.yaml with `transcript` (filename only, not full path) via `Library.find(name).complete_transcript!([filenames])`.

**Refinement note:** When `transcript_refinement: true`, each `transcribe-audio` agent reviews and corrects its transcript in place before returning, using the `user_context` and `footage_summary` the parent passed in. Empty context strings are fine. The parent still only writes `transcript: <filename>.json` to library.yaml after the agent completes.

## Step 2 — Contact sheets (deterministic, no agent)

Run from the project root:

```bash
ruby skills/analyze-video/contact_sheet_job.rb <library-name> <clip> [<clip> ...]
```

Takes an explicit list of clip filenames (including extension, e.g. `P1055016.MP4`). Runs single-threaded — launch multiple invocations in parallel from the main thread when machine headroom allows (a 3-4 way split across cores is usually safe on an M-series Mac). Always rebuilds every sheet for the clips it's given; for clips longer than 10 minutes that includes per-segment sheets covering successive 10-minute slices. Updates library.yaml's `contact_sheet` field for every clip it processes. No LLM — pure ffmpeg.

## Step 3 — Clean scripts (deterministic, no agent)

Run from the project root:

```bash
ruby skills/analyze-video/build_scripts.rb <library-name> <clip> [<clip> ...]
```

Takes an explicit list of clip filenames (including extension). Wraps `script_extractor` over each clip's audio transcript and writes `scripts/script_<clipname>.txt`. Updates library.yaml's `script` field for every clip it processes. Pure JSON parsing — no LLM. Skips clips whose script already exists, so it's safe to re-run. Single-threaded; launch multiple invocations in parallel from the main thread if you want.

## Step 4 — Summaries (Sonnet sub-agents, batched, rolling)

Dispatch `analyze-video` sub-agents on the **Sonnet model**. Sonnet reads the contact sheet with noticeably more visual specificity than Haiku (catches clothing, architecture, camera framing) — worth it since the summaries feed every later roughcut decision.

**Batch 10 clips per sub-agent, up to 10 sub-agents in parallel, with rolling dispatch.** Each sub-agent processes its 10 clips sequentially; batching amortizes the ~5–10s per-agent dispatch overhead. For a 93-clip library that's ~10 sub-agents total instead of 93. Start the next sub-agent as soon as one returns — don't wait for the whole wave of 10 to finish, or you give up ~30% of wall-clock to whichever agent in the wave is slowest.

For each sub-agent, pass a list of 10 clip records inline. Each clip record needs:

- `video_filename` — basename of the video (used in the summary header and reply line)
- `duration` — duration string from library.yaml (e.g. `00:01:19`); the agent renders it in the summary header
- `contact_sheet_path` — absolute path to the `_full.jpg` (from step 2)
- `script_path` — absolute path to the pre-built clean script (from step 3)
- `summary_output_path` — absolute path where the agent should write the summary markdown

As each sub-agent returns its batch, update library.yaml with `summary` for every clip in that batch — `Library.find(name).complete_summary!([filenames])`. The `contact_sheet` and `script` fields were already populated in steps 2 and 3, so the sub-agent return only contributes summaries.

**If a sub-agent returns summaries inline instead of writing them to disk** (sometimes Sonnet hallucinates "the Write tool is blocked" and dumps the markdown into its reply), don't retry blindly — just extract each summary from the agent's response and `Write` it to the matching `summary_output_path` from the parent thread. Then run `complete_summary!` as usual. Faster than redispatching, and the content is already there.

(Per-segment contact sheets generated for long clips live alongside the `_full` sheet on disk and are discoverable by convention — they aren't listed in library.yaml.)

## Step 5 — Confirm footage understanding with the user

Once every summary is written, talk through what the footage actually shows — confirm character names, locations, the narrative through-line, any stray or off-thesis clips, and the user's creative intent for this library. Use plain conversation; only reach for `AskUserQuestion` when offering a discrete choice. As you learn things, update:

- `footage_summary` and `user_context` via `Library.find(name).update_metadata!(footage_summary: ..., user_context: ...)`
- individual `summary_*.md` files when a summary mislabels someone or misses a key detail (e.g., "a man in a tan jacket" → the user's name)

This is the one place to do this thorough pass. Every later `roughcut` planning run inherits the resulting context rather than re-interrogating the library.

## Step 6 — Backup

After all analysis completes, automatically create a backup using the `backup-library` skill.

## Parallel sub-agent pattern (reference)

Used in steps 1 and 4.

**Parent agent responsibilities:**
- Read `library.yaml` and `settings.yaml` once to gather all values needed by sub-agents.
- Launch Task agents passing all needed values **inline in the prompt**.
- Update library.yaml sequentially as agents complete (via the `Library` API — see AGENTS.md).
- Handle errors and retries.

**Child agent responsibilities:**
- Process its assigned clip(s) using only the inputs passed inline by the parent.
- Run WhisperX (transcribe-audio) or read the pre-generated contact sheet + clean script and write the summary markdown in one Write call (analyze-video).
- Return a short structured response with file paths.

Each skill's `agent_prompt.md` documents its own IO contract — including whether the sub-agent reads or writes library.yaml. (Spoiler: it never writes library.yaml. Only the parent writes, via the `Library` API.)

## If the user requests a rough cut before analysis completes

Warn: "I can create a rough cut now, but I'll do a better job after analyzing all the footage. Continue anyway?" If the user confirms, proceed. Otherwise, wait for analysis to complete.
