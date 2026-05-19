# Changelog

All notable changes to ButterCut will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Footage analysis is dramatically faster.** Visual transcripts (LLM-driven, frame-by-frame) are gone. Each clip now gets a contact sheet (a single image grid covering the whole clip with timestamps burned in), a clean dialogue script (no timing weight), and the existing markdown summary. Contact sheet generation is pure ffmpeg — no LLM in that step — so analysis runtime drops from roughly 1× footage length to a small fraction of it. The roughcut agent reads the contact sheet to "see" a clip at a glance, the script for cheap dialogue context, and the audio transcript only when it needs word-level cut timing.
- **`summarize-video` skill folded into `analyze-video`.** One skill, one parent dispatch, one sub-agent per clip.
- **New `build_contact_sheets.rb` orchestrator.** Takes a library name plus an explicit list of clip filenames; generates `_full.jpg` for each (plus 10-minute chunk sheets for clips longer than 10 minutes) and updates library.yaml. Skips clips that already have a sheet. Single-threaded by design — the parent agent decides how many invocations to run in parallel based on machine headroom.
- **New `build_scripts.rb` orchestrator.** Takes a library name plus an explicit list of clip filenames; writes a clean dialogue script per clip from its audio transcript and updates library.yaml. Pure JSON parsing — no LLM. Skips clips whose script already exists. Single-threaded by design — parent agent parallelizes by launching multiple invocations.
- **Analyze-video sub-agents now write each summary in one shot.** The four-placeholder skeleton + four-Edit dance is gone; the sub-agent reads the contact sheet and script, then issues a single `Write` with the full markdown. Drops per-clip from 7 tool calls to 3 — roughly halves the slowest-batch wall.
- **Library schema:** new `script:` and `contact_sheet:` fields per video; `visual_transcript:` is deprecated. Old libraries keep their `visual_*.json` files on disk — no migration runs. Re-run analysis on an old library to populate the new fields.
- **Skills moved to top-level `skills/`.** Shipped skills now live in `skills/` so Claude Code, Codex, and other agentic CLIs that read `skills/` natively all find the same files. `.claude/skills` is a git-tracked symlink pointing to `../skills`, so Claude Code keeps working unchanged. On a fresh clone this is automatic; if you're updating an old install via `update-buttercut`'s rsync path (no git), you may need to delete the old `.claude/skills/` directory once so the symlink can take its place.
- **Project instructions moved to `AGENTS.md`.** `CLAUDE.md` is now a one-line `@AGENTS.md` import, so non-Claude agents that read `AGENTS.md` by convention pick up the same rules.

### Removed
- `summarize-video` skill (folded into `analyze-video`).
- `skills/analyze-video/prepare_visual_script.rb` (no more visual transcripts).
- `skills/analyze-video/summary_skeleton.rb` (sub-agents write the summary in one shot now; no placeholder skeleton needed).

## [0.6.0] - 2026-05-03

Honestly, this is the biggest single release for ButterCut so far. 0.6 has dramatically better rough cuts driven by the user, sharper editing thanks to new word-by-word timing, and process improvements that help ButterCut make sense of all your footage without getting overwhelmed. It's So. Much. Better.

**Tighter cuts.** ButterCut can now trim at the word level. Before, edits could basically only land on sentence boundaries, so a clip carried whatever filler or restarts came with it. Now it uses the transcript's per-word timing and trims inside a sentence down to hundredths of a second.

**Rough cuts you actually want.** Rough cut creation used to be one step where Claude inferred what you wanted and built it. This was often the wrong story or the wrong footage. Now planning happens first. ButterCut reads summaries of your footage, proposes 2–3 narrative directions, and iterates with you until you approve a plan.

### Added
- **Planning step.** Before building anything, ButterCut now reads a short summary of every clip, proposes 2–3 narrative directions, and iterates with you on the structure and beats until you approve a plan. Only then does it build the cut.
- **Optional "save to Desktop" after export.** ButterCut asks once whether to copy the exported edit to your Desktop, and remembers your answer.

### Changed
- **Rough cut creation split into planning and building.** Planning is conversational and happens with you. Building is mechanical and happens out of the way once you've approved the plan. The split keeps the conversation focused on creative decisions instead of file-shuffling.
- **Less technical user-facing language.** A lot of ButterCut users aren't developers, so Claude now talks like an editor — rough cut, transcript, "I'll re-export it for Final Cut" — instead of leaking file formats, internal field names, or the names of the tools doing the work behind the scenes.
- **Single-track timelines reinforced.** ButterCut produces one sequential video track — no B-roll over voiceover, no cutaways layered over continuing voiceover. For now. ;-)
- **Tidier temporary files.** All scratch files now go in one place inside the project, instead of scattering across the system.

## [0.5.0] - 2026-04-24

### Added
- **Improve video analysis performance and accuracy.** After WhisperX runs, ButterCut now optionally reviews transcripts and fixes misheard words using your library's context — names, places, technical jargon, speakers with accents, etc. On by default for new libraries.
- **Global preferences.** Your editor (Final Cut / Premiere / Resolve) and Whisper model preference now live in one `libraries/settings.yaml` and apply to every new library.
- Contribution guidelines in the README.

### Changed
- **Faster, more accurate default transcription.** Default Whisper model is now `small` (was `medium`). Paired with the new proofreading step, this is both faster and more accurate than the old default. Larger, slower models are still available if you want.

  Benchmark on a 5-minute speech clip (CPU, float32):

  | model  | wall time | speedup vs realtime | user CPU  |
  | ------ | --------- | ------------------- | --------- |
  | medium | **90.1s** | 3.3×                | 143.0 s   |
  | small  | **47.7s** | 6.3×                | 82.8 s    |

- Renamed `footage_description` → `footage_summary` in the library schema. Migration script below handles existing libraries.
- Release workflow now runs `bundle install` after a version bump so `Gemfile.lock` stays in sync.

### Migration
Libraries created before this release have no `transcript_refinement` field. Their existing transcripts were never refined, so the key defaults to `false` on migration — new libraries still default to `true` via the template. If you want refinement on an existing library, flip the field to `true` in its `library.yaml` after running the migration.

```bash
# Back up your libraries first (creates ZIP in /backups/)
ruby skills/backup-library/backup_libraries.rb

# Add transcript_refinement: false to any library.yaml that's missing the key
ruby scripts/002_migrate_add_transcript_refinement.rb --all
```

## [0.4.0] - 2026-02-24

### Changed
- **~2x faster roughcut generation** - Removed scratchpad workflow and increased transcript chunk size from 1000 to 5000 lines (~3.5min vs ~6-7min)
- **Persistent editor preference** - Editor choice (fcpx/premiere/resolve) saved to library.yaml, no longer prompted each time
- Replaced shell-out code generation in export script with direct ButterCut require under bundle exec
- Simplified transcript combining: replaced Ruby script with shell pipeline for NDJSON output
- Temporary files now use project `tmp/` directory instead of system `/tmp`

### Added
- Claude Code project settings for auto-allowing common workflow operations (skills, ffprobe, ffmpeg, whisperx)
- Worktree creation skill for working with libraries across git worktrees

### Fixed
- Timestamp variable not persisting across shell calls during export

## [0.3.0] - 2025-12-01

### Changed
- **BREAKING**: Simplified library.yaml transcript fields
  - `transcript_path` → `transcript` (filename only, not full path)
  - `visual_transcript_path` → `visual_transcript` (filename only, not full path)
  - Transcripts are always stored in `libraries/[library-name]/transcripts/`
  - Reduces library.yaml size by ~45% for large libraries
- **Hundredths-of-second timestamp precision** in roughcuts
  - Timestamps now use `HH:MM:SS.ss` format instead of `HH:MM:SS`
  - Preserves timing within ~10ms of WhisperX transcript data
  - Prevents clipping words at edit points

### Removed
- `file_size_mb` field from library.yaml (not used for editorial decisions)

### Migration
```bash
# Back up your libraries first (creates ZIP in /backups/)
ruby skills/backup-library/backup_libraries.rb

# Migrate library.yaml files to new field names
ruby scripts/001_migrate_0.2_to_0.3.rb --all
```

## [0.2.0] - 2025-11-25

### Added
- **backup-library skill**: Creates compressed ZIP backups of libraries (transcripts, roughcuts, YAML - not video files)
- **update-buttercut skill**: Automatically downloads and installs the latest version while preserving libraries
- **Flexible setup options**: Simple mise-based install for beginners, advanced checklist for developers
- `.ruby-version` and `.python-version` files for broad version manager support (rbenv, pyenv, asdf, etc.)
- Install location check to warn about problematic directories
- Manual installation documentation at `docs/installation.md`

### Changed
- Restructured setup skill with separate `simple-setup.md` and `advanced-setup.md` guides
- Moved roughcut generation to subtask for streamlined workflow
- Improved Homebrew installation messaging (needs interactive terminal for password prompts)
- Added libyaml dependency to prevent psych extension build failures
- Added note about Ruby compilation time (5-10 minutes via mise)

## [0.1.1] - 2025-01-21

### Added
- DaVinci Resolve support via FCP7 XML (xmeml version 5) format
- Release skill for automated version management and publishing workflow
- Centralized version management via `ButterCut::VERSION` constant

### Changed
- Improved library management with better documentation and workflow guidelines
- Enhanced CLAUDE.md with clearer library setup and parallel transcription patterns

### Fixed
- Gemspec now references version from `lib/buttercut/version.rb` for single source of truth

## [0.1.0] - 2025-01-15

### Added
- Initial release of ButterCut gem
- FCPX XML generation (FCPXML 1.8 format)
- FCP7/Premiere XML generation (xmeml version 5)
- Automatic video metadata extraction via FFmpeg
- Support for embedded SMPTE timecode
- Claude Code skills:
  - `transcribe-audio`: WhisperX-based audio transcription
  - `analyze-video`: Frame extraction and visual analysis
  - `roughcut`: AI-powered rough cut and sequence creation
- Library-based project management system
- Comprehensive test suite with 65+ specs
