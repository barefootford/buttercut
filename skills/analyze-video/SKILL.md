---
name: analyze-video
description: Internal sub-procedure (not a standalone entry point) — the shared footage-analysis pipeline that produces audio transcripts, contact sheets, and Sonnet-written summaries. Invoked end-to-end by the process-library and reprocess-with-contact-sheets skills; don't trigger it on its own.
---

# Skill: Analyze Video (parent brief)

This is the main thread's playbook for the **Analyze Video** workflow step. Run it after library setup, before any cut work. It covers the three artifacts produced per clip: audio `transcript`, `contact_sheet`, and markdown `summary`. The roughcut agent reads dialogue on demand by running `script_extractor.rb` over the transcript JSON — no separate script artifact.

`SKILL.md` is the parent's dispatch brief. The sub-agent working prompt lives in `agent_prompt.md` — inline its contents when launching a Task agent. Don't pass `SKILL.md`.

## Terminology

- **User-facing:** call it "footage analysis" or "analyzing footage."
- **Internal/file names:** "transcription" (library.yaml field `transcript`, etc.).

## Prerequisites

- Library setup is complete (`library.yaml` exists, schema is current — run migrations from AGENTS.md if not).
- Read `libraries/settings.yaml` directly for `whisper_model`. For library fields, read the snapshot via `ruby lib/buttercut/library.rb <name> summary` and pull the values you need from the JSON — don't parse library.yaml inline.

At this point, create a todo list, visible to the user, with high-level, non-technical steps so they can follow the overall plan for processing the library. Include caffeination steps only if they've opted in. e.g.:

```
- [ ] Keep Mac Awake with Caffeinate 
- [ ] Create transcripts (0/30)
- [ ] Analyze footage (0/30)
- [ ] Turn off Mac Caffeinate 
- [ ] Review the footage together
```

These public todos map onto the steps below: "Keep Mac Awake with Caffeinate" is Step 1 and "Turn off Mac Caffeinate" is Step 6; "Create transcripts" covers the mechanical run in Step 2 plus the optional refinement pass in Step 3 (advance its count from Step 2's `[transcript …]` progress lines; hold it in-progress through Step 3 when refinement is on); "Analyze footage" tracks the summaries in Step 4 (advance its count as clips are summarized, *not* after contact sheets); "Review the footage together" is Step 5.

In the public chat, refer to these non-technical steps. Keep the technical work (WhisperX, contact-sheet generation, Sonnet summaries) behind the scenes.

## Step 1 — Prevent sleep during processing

Before starting analysis, ask the user (via `AskUserQuestion`): "Processing can take a while — want me to keep your computer awake until it's done?" Options: "Yes (Recommended)" and "No".

If yes, start caffeinate in the background:

```bash
caffeinate -i -w $$ &
CAFFEINATE_PID=$!
```

This prevents idle sleep for the lifetime of the shell. Store the PID — you'll kill it in Step 6 once analysis is finished. (Backup is handled by the calling skill — `process-library` — after this skill returns.)

## Step 2 — Process footage (transcripts, then contact sheets)

(If you reached this skill directly rather than via `process-library`, first tell the user: "Found [N] videos ([total size]). Starting footage analysis...")

This is two mechanical commands you run **one after the other** — transcripts first, contact sheets second. **Never run them at once**: WhisperX is RAM-hungry, and overlapping the two is what we're avoiding. Don't hand-roll either with sub-agents; each runs identically every time, ~2 clips at a time, recording each clip into library.yaml the moment it finishes. Both are idempotent — they only touch clips still missing that artifact — so a re-run finishes only what's left. They will run in a minature Sidekiq-like job service. You'll run the command and then watch the log file that will be returned to watch progress.

**Step 2a — Transcripts.** If using Claude Code, run with `run_in_background: true` on the Bash tool. Otherwise use correct tool/argument to run in background.

```bash
ruby lib/buttercut/process_footage.rb transcripts <library-name>
```

Immediately after launching, set up a `Monitor` or equivalent on the log file to receive a notification for each completed or failed clip:

```bash
tail -f tmp/logs/processing/<library-name>/$(date +%Y-%m-%d).log | grep --line-buffered -E "TranscribeJob  (done|error)|transcript: [0-9]+/[0-9]+|Error|error:|failed|Traceback"
```

```bash
ruby lib/buttercut/library.rb <name> pending transcript   # JSON list; done = N − its length
```

Update "Create transcripts 5/20" ie, number_of_clips_complete/total_number_of_clips as clips finish so the user can see progress. When the background task completes it exits non-zero if any clip failed. On failure, re-run once. If it fails again, investigate and then either create a fix so we handle it elegantlyy or inform the user about the problem with the clip and potentially pull it from the library.

**Wait for 2a to finish before starting 2b.**

**Step 2b — Contact sheets.** Once transcripts are done, build the sheets (a fast ffmpeg pass — foreground is fine):

```bash
ruby lib/buttercut/process_footage.rb contact-sheets <library-name>
```

Contact sheets stay behind the scenes — don't surface them as a public count. Mark "Create transcripts" done once 2a has finished and any refinement (Step 3) is complete.

Tuning (optional): both steps read `parallel_jobs` from `libraries/settings.yaml` (default 2); override for one run with `--jobs N`. Each writes a timestamped log under `tmp/logs/processing/<library>/` for after-the-fact review.

**Reprocessing.** Each step skips clips that already have its artifact. To redo one — say a transcript that misheard a name — re-run that step with `--force --clips NAME.mov`. `--force` alone rebuilds every clip.

## Step 3 — Refine transcripts (judgment — only if `transcript_refinement: true`)

Refinement is the one part of transcription that's a judgment call — fixing misheard proper nouns from library context — so it stays a model step, run *after* the mechanical pass. **Skip this entire step if the library's `transcript_refinement` is `false`.**

When it's `true`, dispatch refinement sub-agents (2-4 in parallel, rolling) over the transcripts Step 2a just wrote. Inline `skills/transcribe-audio/refine_instructions.md` as each sub-agent's prompt and pass, inline:

- `transcript_path` — absolute path to the clip's transcript JSON under `libraries/<library>/transcripts/`
- `user_context` and `footage_summary` — current values from `ruby lib/buttercut/library.rb <name> summary` (empty strings are fine; refinement still catches nonsense-token and self-witness fixes)

Sub-agents edit the transcript JSON in place and return a short list of corrections. They do NOT touch library.yaml — Step 2a already set the `transcript` field. Mark the public "Create transcripts" todo done once refinement completes.

## Step 4 — Summaries (Sonnet sub-agents, batched, rolling)

Dispatch `analyze-video` sub-agents on the **Sonnet model**. Sonnet reads the contact sheet with noticeably more visual specificity than Haiku (catches clothing, architecture, camera framing) — worth it since the summaries feed every later cut decision.

**Batch 10 clips per sub-agent, up to 10 sub-agents in parallel, with rolling dispatch.** Each sub-agent processes its 10 clips sequentially; batching amortizes the ~5–10s per-agent dispatch overhead. For a 93-clip library that's ~10 sub-agents total instead of 93. Start the next sub-agent as soon as one returns — don't wait for the whole wave of 10 to finish, or you give up ~30% of wall-clock to whichever agent in the wave is slowest.

For each sub-agent, pass a list of 10 clip records inline. Each clip record needs:

- `video_filename` — basename of the video (used in the summary header and reply line)
- `duration` — duration string from library.yaml (e.g. `00:01:19`); the agent renders it in the summary header
- `contact_sheet_path` — absolute path to the `_full.jpg` (from step 2)
- `transcript_path` — absolute path to the audio transcript JSON (from step 2); the sub-agent extracts dialogue on demand via `script_extractor.rb`
- `summary_output_path` — absolute path where the agent should write the summary markdown. Don't hand-build this filename; ask the library for the canonical path: `ruby lib/buttercut/library.rb <name> field_path summary <clip>` (handles the `summaries/summary_<clip>.md` convention for you, with or without the file extension)

As each sub-agent returns its batch, update library.yaml with `summary` for every clip in that batch:

```bash
ruby lib/buttercut/library.rb <name> complete summary <filename> [<filename>...]
```

The `contact_sheet` field was already populated in step 2, so the sub-agent return only contributes summaries.

**If a sub-agent returns summaries inline instead of writing them to disk** (sometimes Sonnet hallucinates "the Write tool is blocked" and dumps the markdown into its reply), don't retry blindly — just extract each summary from the agent's response and `Write` it to the matching `summary_output_path` from the parent thread. Then run the `complete summary` command as usual. Faster than redispatching, and the content is already there.

(Per-segment contact sheets generated for long clips live alongside the `_full` sheet on disk and are discoverable by convention — they aren't listed in library.yaml.)

Don't move forward until summaries are complete. Advance the "Analyze footage" count as clips are summarized; mark it done when finished.

**Images.** Still images skip Steps 2–3 entirely (no audio to transcribe, no contact sheet to build) — a `summary` is the only artifact they need, and they show up in `ruby lib/buttercut/library.rb <name> pending summary` right alongside videos. The image *is* the thing to look at, so summarize it directly: read the image file (it's small) from the main thread or a Sonnet sub-agent and write a 3–4 sentence description — subjects, setting, composition, any on-image text — to the canonical path from `ruby lib/buttercut/library.rb <name> field_path summary <image-filename>`. Note image clip keys include the extension (`title-card.png` → `summaries/summary_title-card_png.md`), which `field_path` handles for you. Then record it the same way: `ruby lib/buttercut/library.rb <name> complete summary <image-filename>`.

## Step 5 — Confirm footage understanding with the user

(This is the "Review the footage together" todo.) Once every summary is written, talk through what the footage actually shows — confirm character names, locations, the narrative through-line, any stray or off-thesis clips, and the user's creative intent for this library. Use plain conversation; only reach for `AskUserQuestion` when offering a discrete choice. As you learn things, update:

- `footage_summary` and `user_context` via `ruby lib/buttercut/library.rb <name> update_metadata footage_summary "..."` (and the same with `user_context`)
- individual `summary_*.md` files when a summary mislabels someone or misses a key detail (e.g., "a man in a tan jacket" → the user's name)

This is the one place to do this thorough pass. Every later roughcut planning run inherits the resulting context rather than re-interrogating the library.

## Step 6 — Stop caffeinate

If you started caffeinate in Step 1, kill it now:

```bash
kill $CAFFEINATE_PID 2>/dev/null
```

## Parallel sub-agent pattern (reference)

Used in steps 3 and 4.

**Parent agent responsibilities:**
- Read `library.yaml` and `settings.yaml` once to gather all values needed by sub-agents.
- Launch Task agents passing all needed values **inline in the prompt**.
- Update library.yaml sequentially as agents complete (via the `Library` API — see AGENTS.md).
- Handle errors and retries.

**Child agent responsibilities:**
- Process its assigned clip(s) using only the inputs passed inline by the parent.
- Refine a transcript JSON in place (refinement) or read the pre-generated contact sheet, extract dialogue from the transcript via `script_extractor.rb`, and write the summary markdown in one Write call (analyze-video). (WhisperX is no longer a sub-agent — `process_footage.rb transcripts` runs it in Step 2a.)
- Return a short structured response with file paths.

Each skill's `agent_prompt.md` documents its own IO contract — including whether the sub-agent reads or writes library.yaml. (Spoiler: it never writes library.yaml. Only the parent writes, via the `Library` API.)

## If the user requests a rough cut before analysis completes

Warn: "I can create a rough cut now, but I'll do a better job after analyzing all the footage. Continue anyway?" If the user confirms, proceed. Otherwise, wait for analysis to complete.
