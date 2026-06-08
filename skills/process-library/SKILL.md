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
- Read the snapshot — one call gives you top-level metadata plus the clip-completion breakdown (`media_count`, `incomplete_count`, and the list of incomplete clips with their missing fields):
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

If the user is adding new footage to an existing library, append the clips first (video clips and/or still images):

```bash
ruby lib/buttercut/library.rb <name> add_media /abs/new1.mov /abs/photo.png
```

**Convert HEIC/HEIF photos first.** iPhone photos are usually `.heic`, which the editors don't reliably import. `add_media` rejects a raw HEIC on purpose. If any new files end in `.heic`/`.heif`, follow the conversion procedure in `skills/create-library/SKILL.md` → "Step 2.5 — Convert HEIC/HEIF photos" (ask where the JPEGs should go, convert with `ruby lib/buttercut/media.rb convert`, never modify the originals), then pass the resulting `.jpg` paths to `add_media`.

Each new video entry starts with empty `transcript`, `contact_sheet`, and `summary` — empty means "todo." Image entries start with just an empty `summary` (stills have no transcript or contact sheet). The analysis steps below are idempotent and only touch clips missing an artifact, so they'll process just the new clips — and they skip transcription and contact sheets for images automatically.

If you're simply resuming or processing a freshly created library, skip this step.

## Step 3 — Analyze footage

Inform the user: "Found [N] videos ([total size]). Starting footage analysis..."

Follow `skills/analyze-video/SKILL.md` end-to-end. That skill covers keeping the Mac awake during processing (caffeinate), footage processing (transcripts then contact sheets, two deterministic `process_footage.rb` runs), optional transcript refinement, summaries (Sonnet sub-agents, batched + rolling), and the post-analysis footage-understanding pass.

Images are handled automatically: `process_footage.rb` skips transcription and contact sheets for stills (there's no audio and the photo is its own overview), so the only analysis an image needs is a summary, written by the analyze-video sub-agent reading the image directly.

Progressively update `footage_summary` as transcripts come in — 1-3 sentences covering subjects, locations, activities, visual style:

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

## Step 5 — Backup

After all analysis completes, automatically create a backup using the `backup-library` skill, scoped to just the library you processed: `ruby lib/buttercut/backup_libraries.rb --library <library-name>`. This writes a single archive under `~/Documents/buttercut-video-editor-backups/<library-name>/` (or wherever `backups_dir` in `libraries/settings.yaml` points). If `backups_dir` isn't set yet, the script silently uses the default — don't prompt during process-library.

## Notes

- A single `tmp/` directory inside the buttercut project root is used for all temporary files. Create subdirectories as needed and delete after use.
- Reprocessing footage: `process_footage.rb` only handles clips missing an artifact. To rebuild ones that already exist, re-run the relevant step (`transcripts` or `contact-sheets`) with `--force` (optionally `--clips a.mov,b.mov`). See analyze-video Step 2.
- Migrations: every time you read a library.yaml, check its schema against `templates/library_template.yaml`. If anything's missing or renamed, run `ruby lib/buttercut/library.rb migrate` to migrate all libraries at once. See AGENTS.md → Critical Principles for the migration trigger list.
