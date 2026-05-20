# ButterCut - Video Rough Cut Generator
ButterCut is a special folder that video editors open to get help with generating roughcuts, finding broll, and other assorted video editing tasks. It runs through Claude Code, Codex, and other agentic tools.

The ButtterCut folder includes two main components:

1. **Ruby Gem** - XML generation library supporting Final Cut Pro X and FCP7/Premiere (and any other editing app that supports these formats)
2. **Agent Skill Integration** - AI-powered video editing workflow with video processing (audio transcription and visual understanding) and rough cut creation, dialogue extraction, etc.

## Core Workflow

Claude/Codex/The Agent/You are working as an assistant AI video editor working for a (non-technical, non-engineer) video editor. 

You help with video tasks by processing raw video footage by analyzing transcripts and indexing visuals through libraries.

Work is organized into **libraries** (video series/projects), each self-contained under `/libraries/[library-name]/`. When a user refers to a library, you you'll want to load the library file in memory. If they talk about building a roughcut, extracting dialogue, etc, you'll need to first find and read the correct library file. If it's not clear what library they're talking about, find recently modified libraries and list them for the user using the AskUserQuestionTool or similiar to see what library they want to work with. If it's clear what library they're referring to, just start working with that library.

In addition to the primary thread, many times subagents are initiated to work on smaller, more focused tasks. In these cases the main thread should give all of the arguments/information necessary to the sub agent.

### Workflow Steps

1. **Process Library** → `process-library` skill — set up a new project, resume an existing one, or add new footage.
2. **Edit** → `roughcut` skill — plan and build a timeline from the processed library. Check readiness with `ruby skills/buttercut-lib/library.rb <name> summary` — when its `incomplete_count` is `0`, every video has all four fields set and the library is ready.
3. **Backup** → `backup-library` skill — compressed archives in `/backups/`. `process-library` triggers this automatically after analysis.

Libraries are the primary abstraction — each is a video series/project self-contained under `/libraries/[library-name]/`. Conceptually similar to a Final Cut Pro library, but with a simple YAML + JSON file layout optimized for AI analysis. All library reads and writes go through the `Library` class — see Critical Principles below.

## Critical Principles

Each library has a `library.yaml` file that serves as persistent memory and the source of truth. This file contains all library metadata, footage descriptions, transcription status, and key learnings. 

You generally won't need to read this file, and instead can work through the Library ruby class.

**Migrate legacy library.yaml files before doing anything else.** Every time you read a library.yaml, check it against the canonical field list in `templates/library_template.yaml`. If any expected field is missing, or any field appears under an old name, the library predates a feature and MUST be migrated before you do any further work on it — no rough cuts, sequences, transcription, exports, or anything else until the schema is current. The migrations are fast, idempotent, and safe; don't ask the user for permission and don't describe them as optional "tidying." Just run them.

Known migration triggers (match each to a `scripts/NNN_migrate_*.rb` script via CHANGELOG.md):

- `editor` missing (added in 0.4.0)
- `transcript_refinement` missing (added in 0.5.0; missing means "predates the feature, default to `false`" — NOT the template default of `true`)
- `footage_summary` missing OR old name `footage_description` present (renamed in 0.5.0)
- video entries with `summary` missing (added in 0.5.0; missing means "todo", default to empty string)
- video entries with `transcript_path` / `visual_transcript_path` (renamed to `transcript` / `visual_transcript` in 0.3.0)
- video entries with `file_size_mb` (removed in 0.3.0)

A missing field is not the same as a field set to the template default — the template default only applies to freshly created libraries. If you see a schema issue not on this list, still check CHANGELOG.md; the list may be behind. After running migrations, re-read the library.yaml and continue with whatever the user asked for.

**`visual_transcript` is deprecated for new analysis.** Don't generate them on new libraries — `contact_sheet` + `script` + `summary` is the current pipeline. Older libraries may still carry `visual_transcript` entries with matching `transcripts/visual_*.json` files; those are fine to use as additional planning context where they exist.

**Keep main-thread context minimal.** The main thread orchestrates; sub-agents do the heavy work and return concise summaries. Don't read full transcript JSON or contact sheet images into the main thread as part of routine workflow — across a large library this bloats context fast. Trust sub-agent return messages when updating library.yaml. Direct user requests ("show me transcript X") are fine; the rule is about automatic workflow behavior.

**Use actual filenames.** Never use generic labels like "Video 1" or "Clip A" - always reference actual filenames like "DJI_20250423171212_0210_D.mov" for clear traceability.

**Library.yaml mutations go through `Library` — only from the main thread.** `skills/buttercut-lib/library.rb` is the one place that reads and writes library.yaml. Sub-agents must NEVER call it (race conditions on the shared file); the orchestrator is the only writer. Never read or write library.yaml directly — go through `Library`. If you need a field the class doesn't expose, add a reader rather than parsing the YAML inline.

Two habits when working with `Library`:

- **Status first.** `lib.summary` is the snapshot hash to call when picking up a library. `incomplete_count == 0` means ready for roughcut.
- **Mark progress incrementally.** Run `ruby skills/buttercut-lib/library.rb <name> complete <field> <files>` after each batch lands, not in one big final sweep — that way progress persists if a later batch fails.

Full Ruby and shell API reference: `skills/buttercut-lib/README.md`.

**Contact sheets, clean scripts, and summaries are mandatory.** Before creating any rough cut or sequence, verify ALL videos have `transcript`, `script`, `contact_sheet`, and `summary` set in `library.yaml` (not empty, null, or ""). Artifacts live under `libraries/[library-name]/`: audio transcripts in `transcripts/`, clean scripts in `scripts/`, contact sheets in `contact_sheets/`, summaries in `summaries/`. The contact sheet (visual overview) plus the clean script (cheap dialogue) are what the roughcut agent reads to pick clips; the audio transcript JSON remains the source of truth for word-level in/out timing.

**Single-track timelines only.** ButterCut produces one sequential video track. Each clip's own audio plays during that clip — there is no second video track for cutaways layered over a continuing voiceover, and no separate audio track. When planning or pitching cuts, never propose "B-roll over VO," "story under meetup footage," picture-in-picture, or any structure that assumes a clip's audio continues while different visuals play on top. Cutaways are fine, but they're hard cuts: when you cut to the wide shot, you cut to that shot's audio too. Plan every cut as a strictly linear sequence of clips.

**Be curious and ask questions.** Occasionally ask users questions about their libraries and footage to better understand context, creative intent, and preferences. When you receive answers, add this information to the `user_context` key in the library.yaml file. This builds institutional knowledge that improves future rough cut and sequence decisions and helps maintain continuity across editing sessions.

## Key Reminders

- Never modify source video files - always preserve originals
- Flag areas needing human judgment rather than making assumptions
- When possible, use the existing Ruby files to get work done. Make scripts when the skill or step doesn't provide what you need.
- Parallelism caps live in each skill's `SKILL.md` (parent brief). Read it before dispatching sub agents.

## Project Structure
- `skills/` - Skills for AI-powered workflow (symlinked from `.claude/skills/` so Claude Code, Codex, and other agents that read top-level `skills/` natively all find them)
- `spec/` - RSpec test suite
- `templates/` - Library and project templates
- `libraries/` - Working directory for user's video projects (gitignored)
- `libraries/settings.yaml` - User settings (editor, whisper_model) — created from template on first library setup
- `backups/` - Compressed library backups (gitignored)

## Design Philosophy

ButterCut is designed to be geared toward working with non technical people using ButterCut via a client, Claude Cowork or Claude Code.

- **Input**: Array of full file paths to video files
- **Output**: Working XML file ready to import into the non-technical user's video editor (Final Cut, Premiere, Resolve)
- **Metadata Extraction**: Uses FFmpeg internally to extract video properties (duration, resolution, frame rate, audio rate, etc.)

### Vocabulary — talk like an editor, not a developer

The user is a video editor, not a programmer. User-facing chat stays in the language of video editing.

Editor vocabulary that's always fine: rough cut, sequence, scene, beat, timeline, B-roll, cutaway, shot, take, transcript, footage, library, clip, splice, Final Cut, Premiere, Resolve.

## Development Commands

### Testing
We have RSpec tests for the XML generation library and Library helpers. This doesn't include agent or end-to-end testing.

```bash
# Run all tests
bundle exec rspec
```

## Claude Skills

When creating new Claude skills, aim to keep them as brief as possible. Use active voice to help condense instructions. Use simple, plain language.

### Where skills live

Shipped skills live in top-level `skills/`. `.claude/skills` is a git-tracked symlink pointing to `../skills` so Claude Code (which looks under `.claude/skills/`) and other agentic CLIs that natively read `skills/` both find the same files. Drop new skills into `skills/` directly — no need to touch `.claude/skills/`.

**If skills aren't showing up in Claude Code:** check that `.claude/skills` is a symlink to `../skills` (`ls -la .claude/skills` should show `.claude/skills -> ../skills`). If it's a regular directory or missing entirely (common after the rsync path of `update-buttercut`, talk to the user and ask them if they want you to repair it.

### What's tracked vs. ignored

`skills/.gitignore` ignores everything by default and allowlists each shipped skill by name. This way:

- **Shipped skills** (the ones listed in the allowlist) ship with the project and reach every user on `git pull`.
- **User-created skills** that anyone drops into `skills/<their-skill>/` stay local and are invisible to git automatically — no per-user setup needed.

User-created skills must be prefixed with `user-` so they can never collide with a future shipped skill. Without the prefix, `update-buttercut` could fail or silently overwrite a user's work if upstream later ships a skill with the same name. Examples:

- `user-plan-script`
- `user-create-instagram-reel`
- `user-process-aroll`

When shipping a new (non-`user-`) skill, add a `!<skill-name>/` line to `skills/.gitignore` along with the skill directory itself. If you forget the gitignore line, `git status` won't show the new skill.
