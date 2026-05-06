# Changelog

All notable changes to ButterCut will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **B-roll manifest schema (Hyperframes foundation).** New `*.broll.yaml` artifact format and validator (`lib/buttercut/broll_manifest.rb`) that the b-roll director will emit and the Hyperframes render skill / roughcut integration will consume. Each entry pairs a footage timestamp with a template, placement (`overlay` / `cutaway` / `pip`), and template-specific content payload. Canonical example in `templates/broll_template.yaml`. First slice of the Hyperframes integration epic (#63, schema task #64).
- M2: New Project flow + streaming analysis progress UI in the desktop app. Drop a folder of videos, name a project, pick a language, and watch the three-stage pipeline (transcribe → analyze → summarize) run with per-file per-stage progress streamed over JSON-RPC notifications. Removes the last terminal dependency from onboarding.
- Sidecar gains: `inspect_video_paths`, `create_library`, `has_api_key`, `set_api_key`, `start_analysis`, `cancel_job`. Validates Anthropic keys with a Haiku ping; persists to `libraries/settings.yaml` (gitignored). Extracts analyze + summarize prompt content into shared `ui/sidecar/prompts/` files referenced by both the CLI agent and the new sidecar parent.

## [0.6.0] - 2026-05-02

### Added
- **Editorial recipe alongside the rough cut.** Every rough cut now exports an editorial recipe (`<name>.recipe.json`) capturing the agent's editorial intent: per-clip speed ramps, clip color tags, markers, between-clip transitions, an optional title card, render preset, and PowerGrade reference. The XML stays cuts-only; the recipe carries everything else. Schema is versioned and validated by `lib/buttercut/recipe.rb`.
- **DaVinci Resolve apply script.** Each rough cut also generates `<name>_apply.py`, a Python script you drop into Resolve and run from `Workspace > Scripts > Edit > Apply <name>`. It walks the recipe and applies what Resolve's scripting API supports — speed ramps (single-point via `MediaPoolItem.SetClipProperty("Speed", …)`), clip color tags, markers, render preset, and a best-effort PowerGrade lookup. Multi-point ramps and transitions are logged as manual follow-ups. Companion audit doc at `docs/sprints/sprint-01-resolve-api-audit.md` documents the API gaps the script works around.
- **FCPXML 1.10 backend with native speed ramps.** Recipe `speed_ramps` are emitted as `<timeMap>` / `<timept>` waypoints inside the `<asset-clip>`, so DaVinci Resolve preserves speed ramps on FCPXML import without needing the apply script. Easing values map to FCPXML `interp`: `linear` → `linear`; `ease-in` / `ease-out` / `ease-in-out` → `smooth2`. Transitions and color tags still flow through the recipe + apply script.

### Changed
- **`fcpxml` version bumped from 1.8 to 1.10** in all FCPXML output. Existing fixtures and tests updated accordingly.

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
ruby .claude/skills/backup-library/backup_libraries.rb

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
ruby .claude/skills/backup-library/backup_libraries.rb

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
