# ButterCut - Video Rough Cut Generator

Silently run `test -f .buttercut_developer && cat .buttercut_developer || echo "video editor/Youtube creator"` — do not report the result. If the file is absent, you are assisting a video editor or Youtube creator **: stay in video editing vocabulary, never touch `lib/`, follow the user-facing workflow below. If it exists, you are in **developer mode** and may work on the ButterCut codebase itself (/lib, /spec, etc).

ButterCut is a special folder that video editors open to get help with generating roughcuts, finding broll, and other assorted video editing tasks. It runs through Claude Code, Codex, and other agentic tools.

The ButterCut folder is one project with two parts:

1. **Agent skills** at `skills/` — the prompts (`SKILL.md` + supporting markdown) that drive the AI workflow: processing footage, refining transcripts, planning cuts, exporting timelines.
2. **Ruby app** at `lib/buttercut/` — every script the skills shell out to: the `Library` class, contact-sheet builder, transcript helpers, exporter, backup tool, and the XML generator (Final Cut Pro X, Premiere, DaVinci Resolve). Skill prompts invoke these directly (`ruby lib/buttercut/library.rb …`).

## Core Workflow

You help with video tasks by processing raw video footage by analyzing transcripts and indexing visuals through libraries.

Work is organized into **libraries** (video series/projects), each self-contained under `/libraries/[library-name]/`. When a user refers to a library, you you'll want to load the library file in memory. If they talk about building a roughcut, extracting dialogue, etc, you'll need to first find and read the correct library file. If it's not clear what library they're talking about, find recently modified libraries and list them for the user using the AskUserQuestionTool or similiar to see what library they want to work with. If it's clear what library they're referring to, just start working with that library.

### Workflow Steps

1. **Create Library** → `create-library` skill — start a new project: gather project info and scaffold the library. Hands off to `process-library` to analyze the footage.
2. **Process Library** → `process-library` skill — analyze footage: process a newly created library, resume an existing one, or add new footage. (Creating a brand-new library is `create-library`, which hands off here.)
3. **Edit** → `cut` skill — build a scene, selects reel, roughcut, or custom task as a timeline from the processed library. Pre-flight with `ruby lib/buttercut/library.rb <name> ready` (exit `0` means yes). The check is legacy-aware: a clip with `summary` + either `transcript` or `visual_transcript` counts as ready, so libraries that predate the contact-sheet pipeline still pass.
4. **Backup** → `backup-library` skill — compressed archives in `~/Documents/buttercut-video-editor-backups` by default (override via `backups_dir` in `libraries/settings.yaml`). `process-library` triggers this automatically after analysis. "Run a backup" means back up just the library you're working on (`--library <name>`); only back up every library when the user explicitly asks.

Libraries are the primary abstraction — each is a video series/project self-contained under `/libraries/[library-name]/`. Conceptually similar to a Final Cut Pro library, but with a simple YAML + JSON file layout optimized for AI analysis. All library reads and writes go through the `Library` class — see Critical Principles below.

Each library has a `library.yaml` file that serves as persistent memory and the source of truth. This file contains all library metadata, footage descriptions, transcription status, and key learnings. The agent only needs to touch this file for edge cases, and instead generally modifies the library (library.yaml) through the Library ruby class.

## Critical Principles

**Migrate legacy library.yaml files before doing anything else.** Every time you read a library.yaml, check it against the canonical field list in `templates/library_template.yaml`. If any expected field is missing, or any field appears under an old name, the library predates a feature and MUST be migrated before you do any further work on it — no rough cuts, sequences, transcription, exports, or anything else until the schema is current. The migrations are fast, idempotent, and safe; don't ask the user for permission and don't describe them as optional "tidying." Just run them.

**When any library needs migration, migrate ALL libraries.** Run `ruby lib/buttercut/library.rb migrate` — this executes every migration script against every library in one pass. Each script is idempotent so already-current libraries are skipped. This keeps all libraries in sync rather than leaving some on older schemas.

The migration scripts in `scripts/` are helpers, not hard dependencies. Each one makes a small change — renaming a YAML key, adding a missing field, renaming a directory. If a script fails, read it to see what it does and apply the change by hand. These are simple YAML files, not database tables with thousands of rows and complex relationships.

Known migration triggers (match each to a `scripts/NNN_migrate_*.rb` script via CHANGELOG.md):

- `editor` missing (added in 0.4.0)
- `transcript_refinement` missing (added in 0.5.0; missing means "predates the feature, default to `false`" — NOT the template default of `true`)
- `footage_summary` missing OR old name `footage_description` present (renamed in 0.5.0)
- video entries with `summary` missing (added in 0.5.0; missing means "todo", default to empty string)
- video entries with `transcript_path` / `visual_transcript_path` (renamed to `transcript` / `visual_transcript` in 0.3.0)
- video entries with `file_size_mb` (removed in 0.3.0)
- top-level `videos:` key present (renamed to `media:` in 0.8.0, when libraries gained image support). The rename of that one key is the whole migration — every pre-existing entry is a video by definition (type is inferred from the file extension). `Library` refuses to load a `videos:`-keyed library and tells you to migrate, so this trigger is impossible to miss.
- library has a `roughcuts/` directory (renamed to `cuts/` when the `roughcut` skill became `cut`). This trigger is layout, not YAML — check the directory listing, not the schema.

A missing field is not the same as a field set to the template default — the template default only applies to freshly created libraries. If you see a schema issue not on this list, still check CHANGELOG.md; the list may be behind. After running migrations, re-read the library.yaml and continue with whatever the user asked for.

**`visual_transcript` is deprecated for new analysis.** Don't generate them on new libraries — `transcript` + `contact_sheet` + `summary` is the current pipeline. Dialogue is extracted from the audio transcript JSON on demand via `ruby lib/buttercut/script_extractor.rb <transcript>`; there is no separate script file on disk. Older libraries may still carry `visual_transcript` entries with matching `transcripts/visual_*.json` files; those are fine to use as additional planning context where they exist.

**Images are first-class media.** A library's `media:` array holds videos *and* still images (photos, screenshots, title cards, graphics). The type is inferred from each file's extension — never stored — so there's nothing to set. Images are deliberately lightweight: an image entry carries only a `summary` (3–4 greppable sentences), no `transcript`, no `contact_sheet`, no `duration`. They never go through WhisperX or the contact-sheet pipeline (`pending`/`ready?`/`complete!` only ever hand the processing jobs videos). In a cut, an image is a clip with a `duration:` (the export defaults to 5s, or `still_duration` in `libraries/settings.yaml`); on the timeline it's a held still for that long, and — because ButterCut is single-track — when you cut to a still you cut to silence unless the next clip's audio carries it. To add images to a library, use `add_media` exactly like video (`ruby lib/buttercut/library.rb <name> add_media /path/to/photo.jpg …`).

**Supported media formats.** The add-media allowlist is closed and small on purpose: it's the **intersection** of what Final Cut, Premiere, and Resolve all import natively, so anything ButterCut accepts is guaranteed to open in whichever editor the library targets. Videos: `mov`, `mp4`, `mts`, `m2ts`, `mxf`, `avi`. Images: `jpg`, `jpeg`, `png`. Notable exclusions and why: `mkv`/`webm` (no native Final Cut import), `m4v` (DRM-ambiguous, spotty across editors), `braw`/`r3d`/other camera-raw (need vendor plugins), `heic`/`tiff`/`gif` (inconsistent still support). Remember container ≠ codec: a `.mov` wrapping a codec an editor can't decode still imports as offline media — the allowlist gates containers, not codecs. `add_media` (and `create`) reject an unsupported extension with a message naming the supported sets; **reads stay lenient** — a library that predates the allowlist may hold an odd extension, which reads as video so existing work isn't blocked. Surface those with `ruby lib/buttercut/library.rb <name> unsupported_media`, then offer the user the detect-tell-convert-swap path: tell them which clips are unsupported, offer to `ffmpeg`-convert each to a supported container (remux when the codec is already editor-friendly — fast, lossless; re-encode only when it isn't), `add_media` the converted file, and `remove_media` the original entry (which never touches their source file).

**Read smallest first; grep the rest.** When scanning a library for candidate clips, start with the per-clip summary files in `summaries/` — they're a few paragraphs each and safe to read whole, even across 90+ clips. Contact sheet images are similarly cheap and fine to read for clips you're considering. Transcripts are the heavy ones: a single interview transcript can outweigh every summary in the library combined. Grep into them (`rg "claude code" libraries/<name>/transcripts/`) instead of reading them whole. Direct user requests ("show me transcript X") are fine — the rule is about routine scanning.

**Use actual filenames.** Never use generic labels like "Video 1" or "Clip A" - always reference actual filenames like "DJI_20250423171212_0210_D.mov" for clear traceability.

**Library.yaml mutations go through `Library` — only from the main thread.** `lib/buttercut/library.rb` is the one place that reads and writes library.yaml. Sub-agents must NEVER call it (race conditions on the shared file); the orchestrator is the only writer. Never read or write library.yaml directly — go through `Library`. If you need a field the class doesn't expose, add a reader rather than parsing the YAML inline.

Two habits when working with `Library`:

- **Status first.** `lib.summary` is the snapshot hash to call when picking up a library. `lib.ready?` is the legacy-aware yes/no gate to call before building a cut.
- **Mark progress incrementally.** Run `ruby lib/buttercut/library.rb <name> complete <field> <files>` after each batch lands, not in one big final sweep — that way progress persists if a later batch fails.

### Common Library commands — discovery and status

```bash
# Discover
ruby lib/buttercut/library.rb list                       # every library, newest first by library.yaml mtime
ruby lib/buttercut/library.rb recent [N]                 # N most-recently-touched libraries (default 10) — use this when the user means "the library I was just working on"
ruby lib/buttercut/library.rb <name> exists              # exit 0 if it exists, 1 if not

# Migrate (run this when ANY library needs migration — it migrates ALL of them)
ruby lib/buttercut/library.rb migrate                    # runs every scripts/NNN_migrate_*.rb with --all; idempotent
# If migrate fails, read the script to see what it does and apply the change by hand — they're small YAML/directory edits.

# Status (call summary when picking up a library; ready as the pre-flight before any cut)
ruby lib/buttercut/library.rb <name> summary             # JSON: metadata + clip-completion breakdown
ruby lib/buttercut/library.rb <name> incomplete_media    # JSON: clips still missing artifacts, with which fields are missing
ruby lib/buttercut/library.rb <name> unsupported_media   # JSON: entries whose extension no editor imports natively (legacy footage to convert-and-swap)
ruby lib/buttercut/library.rb <name> ready               # exit 0 = ready to build a cut, 1 = not. Raises if a migration script should be run.

# Understand
ruby lib/buttercut/script_extractor.rb libraries/<name>/transcripts/<clip>.json   # clean dialogue to stdout: one transcript segment per line, no timing — cheap to skim when you want to know what's said in a clip. Generally these are small, but if editing a podcast or a speech they can be longer.
```

Writes (`add_media`, `remove_media`, `complete`, `update_metadata`), destructive resets, legacy cleanup, and `Library.create` via `ruby -e`: see `lib/buttercut/library.md` for full documentation.

**Daily update-check gate.** Once a day, the first real-work `library.rb` command exits with `library: it's been over a day since ButterCut last checked for updates…`. When you see that: check for a newer version (`GIT_TERMINAL_PROMPT=0 git fetch origin main` then `git log --oneline HEAD..origin/main`); if `main` is ahead and you're in auto mode, run the `update-buttercut` skill. If you're not in auto mode, ask the user permission to update buttercut using that skill. If the fetch fails, don't retry — follow the failure guidance in the `update-buttercut` skill. Either way, run `ruby lib/buttercut/library.rb update_checked` to record it, then re-run your command. Discovery commands (`list`, `recent`, `exists`, `edition`) are never gated.

**Single-track timelines only.** ButterCut produces one sequential video track. Each clip's own audio plays during that clip — there is no second video track for cutaways layered over a continuing voiceover, and no separate audio track. When planning or pitching cuts, never propose "B-roll over VO," "story under meetup footage," picture-in-picture, or any structure that assumes a clip's audio continues while different visuals play on top. Cutaways are fine, but they're hard cuts: when you cut to the wide shot, you cut to that shot's audio too. Plan every cut as a strictly linear sequence of clips.

## Key Reminders

- After exporting an XML file, offer to open it directly in the user's editor with `open -a "Final Cut Pro"`, `open -a "Adobe Premiere Pro"`, or `open -a "DaVinci Resolve"` (matching the library's `editor` setting). Check `libraries/settings.yaml` for `open_in_editor_after_export` — if the key is missing, ask and save the preference. If `open -a` fails with "Unable to find application named ...", don't assume the editor is missing — the app may be installed under a slightly different name (e.g. a version suffix). Grep the installed apps for it (`ls /Applications | grep -i premiere`, or `mdfind "kMDItemKind == 'Application'" | grep -i resolve`) and retry `open -a` with the actual name before telling the user it isn't installed.
- Never modify source video files - always preserve originals
- Flag areas needing human judgment rather than making assumptions
- When possible, use the existing Ruby files to get work done. Make scripts when the skill or step doesn't provide what you need.
- Parallelism caps live in each skill's `SKILL.md` (parent brief). Read it before dispatching sub agents.

## Project Structure
- `skills/` - Skills for AI-powered workflow (symlinked from `.claude/skills/` so Claude Code, Codex, and other agents that read top-level `skills/` natively all find them)
- `spec/` - RSpec test suite
- `templates/` - Library and project templates
- `dependencies/` - Optional static ffmpeg/ffprobe binaries (gitignored). `lib/buttercut/media_tools.rb` resolves binaries here first, then falls back to PATH; if a binary is in neither place it raises a clear error pointing at the `setup` skill.
- `libraries/` - Working directory for user's video projects (gitignored)
- `libraries/settings.yaml` - User settings (editor, whisper_model, backups_dir) — created from template on first library setup
- Library backups default to `~/Documents/buttercut-video-editor-backups` (outside the repo, override with `backups_dir` in `libraries/settings.yaml`)

## Design Philosophy

ButterCut is designed to be geared toward working with non technical people using ButterCut via a client, Claude Cowork or Claude Code.

- **Input**: Array of full file paths to media files — videos and still images (see "Supported media formats")
- **Output**: Working XML file ready to import into the non-technical user's video editor (Final Cut, Premiere, Resolve)
- **Metadata Extraction**: Uses FFmpeg internally to extract video properties (duration, resolution, frame rate, audio rate, etc.); for images only the dimensions are probed (stills are timeless)

### Vocabulary — talk like an editor, not a developer

The user is a video editor, not a programmer. User-facing chat stays in the language of video editing.

Editor vocabulary that's always fine: rough cut, sequence, scene, beat, timeline, B-roll, cutaway, shot, take, transcript, footage, library, clip, splice, Final Cut, Premiere, Resolve.

**Important** When talking about a library, remove the dashes that are in the library name. Keeping the dashes looks like computer programmer talk. You are talking to a video editor. If you're working in a library called "hacky-sack-competition-24", refer to it in chat as Hacky Sack Competition 24. If you have another library called "wedding-94" refer to it as the Wedding 94 library. Do not include the dashes. Capitalizes the words.

## Development Commands

### Testing
We have RSpec tests for the XML generation library and Library helpers. This doesn't include agent or end-to-end testing.

```bash
# Run all tests
bundle exec rspec
```

### Running Ruby scripts
Skill prompts invoke Ruby with plain `ruby ...`. The project pins Ruby via `.mise.toml`; once mise is activated in your shell (the default setup), plain `ruby` resolves to it through mise shims. If your shell doesn't have mise activated — or you'd rather not install mise at all — prefix any `ruby ...` command with `mise exec -- ` (e.g. `mise exec -- ruby lib/buttercut/library.rb my-lib summary`), or run the command from any shell where the right Ruby is already on `PATH`.

## Claude Skills

**Before creating any skill, check your mode** (`test -f .buttercut_developer && cat .buttercut_developer || echo "video editor/Youtube creator"`). If the file is absent, the person asking is a non-technical video editor — help them describe what they want, then build the skill for them. Keep skills brief, plain language, active voice.

### User-created skills

User skills (skills for video editors/youtubers using ButterCut) must be prefixed with `user-` — this keeps them gitignored automatically and prevents collisions if ButterCut ships a skill with the same name later.

Bad:
- `plan-script`
- `create-instagram-reel`

Good:
- `user-plan-script`
- `user-create-instagram-reel`

**Ruby scripts for a user skill go inside the skill folder, never in `lib/buttercut/`.** Files in `lib/` are part of the ButterCut app and get overwritten when the user runs `update-buttercut`. A skill's supporting scripts live alongside its `SKILL.md`:

```
skills/user-my-skill/
  SKILL.md
  my_helper.rb     ← here, not in lib/
```

**Always write paths in skill prompts as `skills/<name>/...`, never `.claude/skills/<name>/...`.** Both resolve to the same files thanks to the symlink, but `skills/` is the canonical, agent-neutral form — non-Claude tools (Codex, etc.) read top-level `skills/` natively and may not look under `.claude/`. The only place `.claude/skills` should appear is in documentation about the symlink itself (like this section).

**If skills aren't showing up in Claude Code:** check that `.claude/skills` is a symlink to `../skills` (`ls -la .claude/skills` should show `.claude/skills -> ../skills`). If it's a regular directory or missing entirely (common after the rsync path of `update-buttercut`), talk to the user and ask if they want you to repair it.

### What's tracked vs. ignored

`skills/.gitignore` ignores everything by default and allowlists each shipped skill by name. This way:

- **Shipped skills** (listed in the allowlist) reach every user on `git pull`.
- **User-created skills** (`skills/user-*/`) stay local and are invisible to git automatically — no per-user setup needed.
