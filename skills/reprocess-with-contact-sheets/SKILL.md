---
name: reprocess-with-contact-sheets
description: Reset a library's visual analysis (contact sheets, summaries, legacy visual_transcripts) and re-run the current analyze-video pipeline on it. Keeps audio transcripts, cuts, plans, and library metadata. Use when a library was processed under the older pipeline and the user wants to bring it onto the contact-sheet-based one.
---

# Skill: Reprocess With Contact Sheets

Bring a library that was analyzed under the old pipeline (visual_transcripts, no contact sheets) onto the current one (audio transcript + contact sheet + summary). Audio transcripts and any cuts/plans the user has already built are preserved — only the visual layer is rebuilt.

## Step 1 — Pick the library

If the user named a library, use it. If not, list candidates with `ruby lib/buttercut/library.rb recent` and use `AskUserQuestion` to pick one.

Verify it exists and read the snapshot:

```bash
ruby lib/buttercut/library.rb <name> exists
ruby lib/buttercut/library.rb <name> summary
```

Run any schema migrations from AGENTS.md → Critical Principles before touching anything else.

## Step 2 — Confirm with the user

This is destructive. Tell the user, in plain terms, what will happen:

- Contact sheets, summaries, and any legacy `visual_*.json` transcripts will be deleted.
- Audio transcripts are kept — no re-transcription.
- Your cuts, plans, notes, settings, and editor choice stay untouched.

Use `AskUserQuestion` with a clear yes/no before proceeding. Don't reset on assumption.

## Step 3 — Backup first

Always back up before the reset — this step is mildly risky and a fresh archive is the cheapest insurance. Run the `backup-library` skill against the chosen library and wait for it to finish before touching anything else. If the backup fails, stop and surface the error; don't proceed to the reset.

## Step 4 — Reset

One command wipes contact sheets, summaries, and legacy visual transcripts and clears the matching fields on every clip:

```bash
ruby lib/buttercut/library.rb <name> reset_all_except_audio_transcripts
```

If a clip is missing its audio transcript (some libraries predate even that), the analyze-video skill's step 1 will fill it in on the next step — no special handling here.

## Step 5 — Re-run analysis

Run `skills/analyze-video/SKILL.md`, adapted: the audio transcripts already exist, so skip Step 1a (transcription) for any clip that already has `transcript` set. Run Step 1b (contact sheets) and Step 3 (summaries) for every clip, and skip Step 2 (refinement) — it already ran on these transcripts. Still do Step 4 (confirm footage understanding); the fresh summaries may surface details the old visual_transcripts missed.

Verify readiness before reporting done:

```bash
ruby lib/buttercut/library.rb <name> ready
```

