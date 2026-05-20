---
name: process-library
description: Skill for processing footage (video clips, sounds, photos, etc). Use this when creating a new library, adding new footage (videos) to an existing library, or resuming processing on an existing library.
---

# Skill: Process Library (parent brief)

This skill is the main thread's playbook for the **Setup** and **Analyze Video** workflow steps. Use it whenever the user wants to:

- Start a new project (creates a library, gathers project info, runs analysis end-to-end).
- Return to an existing library to process (loads it and continues from wherever analysis left off).
- Add new footage to an existing library (appends clips, runs analysis just on the new ones).

It orchestrates the full `transcribe-audio` → contact sheets → scripts → summaries pipeline. The mechanics of each analysis step live in `skills/analyze-video/SKILL.md`; this skill calls into them.

## Step 1 — Initialize settings (one-time)

Before any library setup, check if `libraries/settings.yaml` exists. If not, copy from template:

```bash
cp templates/settings_template.yaml libraries/settings.yaml
```

If no previous `settings.yaml` was present, use `AskUserQuestion` to ask the user to confirm or change their defaults (editor and `whisper_model`).

Editor options (label shown to user → value to save):
- Final Cut Pro X → `fcpx`
- Adobe Premiere Pro → `premiere`
- DaVinci Resolve → `resolve`

`whisper_model` options:
- Small (recommended — pairs well with per-library `transcript_refinement`)
- Medium
- Turbo (Large)

Save the shortcode (`fcpx` / `premiere` / `resolve`) to `libraries/settings.yaml`, not the long-form name — downstream export expects the shortcode.

Note: `transcript_refinement` is a **per-library** setting, not global. Ask about it during library setup (Step 3 below), not here.

## Step 2 — Resume or create

Check if a library already exists:

```bash
ruby skills/buttercut-lib/library.rb <name> exists   # exits 0 if it does, 1 if not
```

**If it exists:**
- Skip setup entirely — the library is already configured.
- Read the snapshot first — one call gives you top-level metadata plus the clip-completion breakdown (`video_count`, `incomplete_count`, and the list of incomplete clips with their missing fields):
  ```bash
  ruby skills/buttercut-lib/library.rb <name> summary
  ```
- User is returning to existing work; continue from whatever step is incomplete.

**If the directory exists but `exists` returns 1** (library.yaml missing):
- Check what files are present (`transcripts/`, `roughcuts/`, etc.) and inform the user of the current state.
- Proceed with creating library.yaml to restore consistency.

**If no library directory exists:**
- Proceed to Step 3 to gather project information and create a new library.

To list libraries by recency (for "find a recent library to resume" prompts):

```bash
ruby skills/buttercut-lib/library.rb list
```

## Step 3 — Gather project information (new libraries)

Ask the user these questions one at a time — never all at once.

1. **What do you want to call this project library?**
   - Examples: "bike-locking-video-series", "raiders-2025-highlights", "yo-yo-techniques"
   - Normalize the name: replace spaces with dashes, lowercase, drop special characters (keep alphanumeric and dashes).

2. **Where are the video files located?**
   - Ask: "Where are your video files? You can drag folders or individual files directly into the chat."
   - Verify all files exist before proceeding.
   - Inform the user of what was found: "Found 5 video files totaling 2.3GB."

3. **What language is spoken in these videos?**
   - `AskUserQuestion` with options: "English", "Spanish", and a free-text fallback for other languages.
   - Save the language name (e.g. "English") to library.yaml.
   - Map to a language code (e.g. `en`, `es`, `fr`) behind the scenes when needed for transcription.

4. **Can I proofread the transcripts after they're generated?**
   - `AskUserQuestion` with this exact question: "Can I proofread the transcripts after they're generated? I'll use the video's context to fix mistakes."
   - Options: "Yes — Recommended (Use Claude to refine video understanding)" and "No".
   - Save the boolean to `transcript_refinement` in library.yaml (true for Yes, false for No). Default to `true` if the user skips.

Read the `editor` from `libraries/settings.yaml` — you'll pass it into the create call next.

## Step 4 — Create the library

`Library.create` is the one operation that doesn't have a plain CLI form (kwarg-heavy). Run it via `ruby -e`. It creates the directory tree (transcripts/, scripts/, contact_sheets/, summaries/, roughcuts/, plans/), ffprobes each video for duration, and writes library.yaml in one call:

```bash
ruby -e "require_relative 'skills/buttercut-lib/library'; \
  Library.create('my-library', \
    language: 'en', \
    editor: 'fcpx', \
    transcript_refinement: true, \
    video_paths: ['/abs/foo.mov', '/abs/bar.mov'])"
```

Each video entry starts with empty `transcript`, `script`, `contact_sheet`, and `summary` — empty means "todo", a filename means "done."

If the user later drags in more clips:

```bash
ruby skills/buttercut-lib/library.rb <name> add_videos /abs/new1.mov /abs/new2.mov
```

Then re-run the analyze steps for just the new clips.

## Step 5 — Analyze footage

Inform the user: "Library setup complete. Found [N] videos ([total size]). Starting footage analysis..."

Follow `skills/analyze-video/SKILL.md` end-to-end. That skill covers audio transcripts (parallel sub-agents), contact sheets (deterministic), clean scripts (deterministic), summaries (Sonnet sub-agents, batched + rolling), and the post-analysis footage-understanding pass.

Progressively update `footage_summary` as transcripts come in — 1-3 sentences covering subjects, locations, activities, visual style:

```bash
ruby skills/buttercut-lib/library.rb <name> update_metadata footage_summary "subjects/locations/activities/visual style"
```

The full understanding pass at the end of analyze-video is where this gets refined.

Analyze ALL videos before offering to create rough cuts.

## Step 6 — Backup

After all analysis completes, automatically create a backup using the `backup-library` skill.

## Notes

- A single `tmp/` directory inside the buttercut project root is used for all temporary files. Create subdirectories as needed and delete after use.
- Migrations: every time you read a library.yaml, check its schema against `templates/library_template.yaml`. If anything's missing or renamed, run the appropriate `scripts/NNN_migrate_*.rb` before anything else. See AGENTS.md → Critical Principles for the migration trigger list.
- Terminology: user-facing, call it "footage analysis" or "analyzing footage." Internally (library.yaml fields, file names), it's "transcription."
