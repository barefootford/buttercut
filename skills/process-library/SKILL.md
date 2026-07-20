---
name: process-library
description: Process the footage in a library — run analysis (transcripts, contact sheets, summaries) on a new library, resume processing on an existing one, or add and analyze new footage. Use when footage needs analyzing.
---

# Skill: Process Library (parent brief)

This skill is the main thread's playbook for the **Analyze Video** workflow step — processing the footage in a library that already exists. Use it whenever the user wants to:

- Analyze a newly created library (this is where `create-library` hands off after scaffolding).
- Return to an existing library and continue from wherever analysis left off.
- Add new footage to an existing library and analyze just the new clips.

It orchestrates the full `transcribe-audio` → contact sheets → summaries pipeline. The mechanics of each analysis step live in `skills/analyze-video/SKILL.md`; this skill calls into them.

## Step 1 — Locate the library

You need an existing library to process. Confirm which one:

```bash
ruby lib/buttercut/library.rb <name> exists   # exits 0 if it does, 1 if not
```

**If it exists:**
- Read the snapshot — one call gives you top-level metadata plus the clip-completion breakdown (`video_count`, `incomplete_count`, and the list of incomplete clips with their missing fields):
  ```bash
  ruby lib/buttercut/library.rb <name> summary
  ```
- Run any schema migrations from AGENTS.md → Critical Principles before touching anything else.
- Continue from whatever step is incomplete.

**If the directory exists but `exists` returns 1** (library.yaml missing):
- Check what files are present (`transcripts/`, `cuts/`, etc.) and inform the user of the current state.
- The library needs scaffolding — use `create-library` to restore consistency, then return here.

**If no library directory exists:**
- There's nothing to process. The user wants to start a new project — use the `create-library` skill first, which will hand back here once the library is scaffolded.

To find libraries by recency (for "the library I was just working on" / "resume a recent one" prompts):

```bash
ruby lib/buttercut/library.rb recent [N]   # N most-recently-touched libraries (default 10)
```

## Step 2 — Add new footage

If the user is adding new footage to an existing library, append the clips first. `add_media` takes videos and images together — the type is inferred from each file's extension:

```bash
ruby lib/buttercut/library.rb <name> add_media /abs/new1.mov /abs/photo.jpg
```

Each new video entry starts with empty `transcript`, `contact_sheet`, and `summary`; each image entry starts with an empty `summary` only. Empty means "todo." The analysis steps below are idempotent and only touch clips missing an artifact, so they'll process just the new clips — and because the transcript/contact-sheet phases are video-only, images flow straight to the summary step.

If you're simply resuming or processing a freshly created library, skip this step.

## Step 3 — Analyze footage

Inform the user: "Found [N] videos ([total size]). Starting footage analysis..."

Follow `skills/analyze-video/SKILL.md` end-to-end. That skill covers keeping the Mac awake during processing (caffeinate), footage processing (transcripts then contact sheets, two deterministic `process_footage.rb` runs), optional transcript refinement, summaries (Sonnet sub-agents, batched + rolling), and the post-analysis footage-understanding pass.

As footage gets processed, don't make assumptions about the the footage based on the filename or camera brand. A `dji` clip is not "drone footage" just because of the brand. DJI also makes gimbal and cinema cameras. Sony makes mirrorless cameras as well as action cameras. Don't characterize footage as aerial, drone, etc unless the footage reveals it.

```bash
ruby lib/buttercut/library.rb <name> update_metadata footage_summary "subjects/locations/activities/visual style"
```

The full understanding pass at the end of analyze-video is where this gets refined.

Analyze ALL videos before offering to create rough cuts.

## Step 4 — Verify readiness

Before reporting analysis complete, confirm the library passes the same gate the `cut` skill uses:

```bash
ruby lib/buttercut/library.rb <name> ready
```

If it exits non-zero, run `ruby lib/buttercut/library.rb <name> summary` to list the incomplete clips, finish the missing artifacts (loop back into whichever analyze-video step owns them), and re-run `ready` until it passes. Don't claim analysis is done while `Library.ready?` is false.

## Step 5 — Check formats

Once the library is ready, check whether all the footage shares one format:

```bash
ruby lib/buttercut/library.rb <name> format_report
```

If `uniform` is `true`, say nothing — matching footage is the normal case.

If `uniform` is `false`, the footage mixes resolutions and/or frame rates. That's allowed — don't block anything — but fold a heads-up into your wrap-up, in editor terms, naming the actual clips. For example: "One heads up: most of your footage is 4K at 29.97, but two clips (IMG_2041.mov, IMG_2044.mov) are 1080p at 25. You can mix them, but when they land on a timeline your editor scales and retimes them to match the rest, which can show up as softer footage, black bars, or slightly stuttery motion. If you'd like, I can convert those two so everything matches."

If the user wants everything uniform, follow `skills/process-library/conform_formats.md` — it converts the outlier clips with ffmpeg (originals untouched) and swaps the library entries to the converted copies while keeping all the analysis.

## Step 6 — Backup

After all analysis completes, automatically create a backup using the `backup-library` skill, scoped to just the library you processed: `ruby lib/buttercut/backup_libraries.rb --library <library-name>`. This writes a single archive under `~/Documents/buttercut-video-editor-backups/<library-name>/` (or wherever `backups_dir` in `libraries/settings.yaml` points). If `backups_dir` isn't set yet, the script silently uses the default — don't prompt during process-library.

## Notes

- A single `tmp/` directory inside the buttercut project root is used for all temporary files. Create subdirectories as needed and delete after use.
- Reprocessing footage: `process_footage.rb` only handles clips missing an artifact. To rebuild ones that already exist, re-run the relevant step (`transcripts` or `contact-sheets`) with `--force` (optionally `--clips a.mov,b.mov`). See analyze-video Step 2.
- Migrations: every time you read a library.yaml, check its schema against `templates/library_template.yaml`. If anything's missing or renamed, run `ruby lib/buttercut/library.rb migrate` to migrate all libraries at once. See AGENTS.md → Critical Principles for the migration trigger list.
