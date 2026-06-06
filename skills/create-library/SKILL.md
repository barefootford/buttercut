---
name: create-library
description: Create a new ButterCut library. Gather library info (name, footage location, language, transcript proofreading) and scaffold the library. Use when the user wants to start a **new** library. Libraries are containers of footage and footage analysis (transcripts, contact sheets, etc). User's may also refer to Libraries as "projects" or similiar. Ask them to confirm if they want a new Library (footage container) or just a new cut (roughcut, select, etc) if unsure.
---

# Skill: Create Library (parent brief)

This skill is performed in the main thread.

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

Save the shortcode (`fcpx` / `premiere` / `resolve`) to `libraries/settings.yaml`.

## Step 2 — Gather project information

First, guard against clobbering an existing library. Once you have a candidate name (after question 1 below), check:

```bash
ruby lib/buttercut/library.rb <name> exists   # exits 0 if it does, 1 if not
```

If it already exists, stop creating — the user is really resuming or adding footage. Switch to the `process-library` skill instead.

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

## Step 3 — Create the library

`Library.create` is the one operation that doesn't have a plain CLI form (kwarg-heavy). Run it via `ruby -e`. It creates the directory tree (transcripts/, contact_sheets/, summaries/, cuts/, plans/), ffprobes each video for duration, and writes library.yaml in one call:

```bash
ruby -e "require_relative 'lib/buttercut/library'; \
  Library.create('my-library', \
    language: 'en', \
    editor: 'fcpx', \
    transcript_refinement: true, \
    video_paths: ['/abs/foo.mov', '/abs/bar.mov'])"
```

Each video entry starts with empty `transcript`, `contact_sheet`, and `summary` — empty means "todo", filename presence means "done."

## Step 4 — Hand off to process-library

The library now exists but no footage has been analyzed. Continue straight into the `process-library` skill to analyze the footage end-to-end. Read that skill and continue processing the library.

Tell the user: "Library setup complete. Found [N] videos ([55 minutes of footage]). Starting footage analysis..." then proceed with `process-library` against the library you just created.

## Notes

- Migrations: creating a fresh library always writes the current schema, so no migration is needed for the new one. But if you touched any pre-existing library here, check its schema against `templates/library_template.yaml` and run `ruby lib/buttercut/library.rb migrate` if anything's missing or renamed. See AGENTS.md → Critical Principles.
- Terminology: user-facing, this is "setting up a project" or "creating a library."
