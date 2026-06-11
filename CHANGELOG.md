# Changelog

All notable changes to ButterCut will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### New & Improved
- **Add photos to your libraries.** Libraries now hold still images (JPEG and PNG) alongside your video footage. Drop them into the same library, give them a quick summary like any clip, and use them in a cut. Add them when you create a library or to an existing one.
- **Put stills in your cuts.** Drop a photo, screenshot, or title card into any cut and set how long it holds on screen (five seconds by default). It exports to Final Cut, Premiere, and Resolve right alongside your video, sized and placed correctly even when the photo is a different shape than your timeline.
- **Set your timeline's frame rate and size.** A cut can now spell out the frame rate and resolution it should export at, which matters for a cut made entirely of photos (where there is no video to copy those settings from). For normal cuts nothing changes: the settings still follow your footage.

### Changed
- A missing ffmpeg/ffprobe now fails fast with a clear "run the setup skill" error instead of a cryptic command-not-found buried in subprocess output. The contact-sheet skill's repair instructions point at the `setup` skill accordingly.
- Setup now pins WhisperX to the tested combination (`whisperx==3.4.2`, `pyannote-audio==3.4.0` — matching `requirements.txt`), so fresh installs can't drift onto untested releases (`pyannote-audio` 4.x breaks whisperx 3.4.2).
- ffmpeg/ffprobe calls now resolve through `MediaTools`: static builds placed in the gitignored `dependencies/` directory take precedence, falling back to PATH. Nothing changes if you don't use `dependencies/` — existing installs keep their PATH ffmpeg.

## [0.7.2] - 2026-06-02

Processing your footage now uses less of your account, your Mac stays awake while it works, and we've fixed a bug in Premiere files so vertical clips export to Premiere right side up.

### New & Improved
- **Footage processing uses 2/3 less tokens.** ButterCut handles your clips through a new ButterCut behind-the-scenes processor, so footage digestion uses 60 percent fewer tokens (account usage) than before. My 37 minute, 93 clip benchmark library takes just 10 percent of my five hour account usage on a Max 5x plan. (Pro accounts should be able to process the same footage and have half their 5 hour usage available.)
- **Your Mac stays awake during analysis.** Long processing runs no longer stall because the machine went to sleep partway through.
- **Open your timeline in one step.** After an export, ButterCut offers to open the cut straight in Final Cut, Premiere, or Resolve.
- **ButterCut checks for updates on its own.** Once a day it looks for a newer version and offers to update, so you stay current without thinking about it.

### Fixed
- **Vertical footage exports to Premiere right side up.** Phone clips and other vertical footage used to land in Premiere lying on their side. They now import upright. Final Cut and Resolve were already correct and are unchanged.
- **Updating older projects is more reliable.** Bringing libraries from earlier versions up to date no longer trips on a few edge cases.

## [0.7.1] - 2026-05-23

Final RubyGems release of ButterCut xml generator. Having the ButterCut (agent) codebase live across skill scripts, shared scripts, and traditional lib code has gotten messy to work on and to explain to agents. I want to do a refactor where we pull all 'business' code into a single directory and it doesn't make sense to have the agent ruby code live with the xml generation code. Using the agent is by far the most popular use of this repository so it makes sense to make it be as easy as possible to work on and use that code. The agent + xml generation project will continue at the same location https://github.com/barefootford/buttercut;

### Changed
- Loading the `buttercut` gem from an installed location now emits a deprecation warning pointing at the GitHub repo. The warning does not fire when ButterCut is run from a source clone, so the agent's own `export.rb` path is unaffected.
- Gemspec summary, description, and homepage updated to reflect deprecation. A `post_install_message` directs new installs to the GitHub repo.

### Notes
- The 0.7.0 and 0.7.1 gems remain published on RubyGems indefinitely; existing installs keep working.
- No functional changes to the XML generator, skills, or agent workflow.

## [0.7.0] - 2026-05-21

This release replaces the LLM-driven visual transcripts with a contact-sheet pipeline, splits roughcut creation across task types under a renamed `cut` skill, and moves shipped skills to top-level `skills/` so non-Claude agentic CLIs find them too.

### Added
- **`reprocess-with-contact-sheets` skill.** Resets a library's visual analysis (contact sheets, summaries, legacy `visual_transcript` entries) and re-runs the current analyze-video pipeline. Keeps audio transcripts, cuts, plans, and library metadata so older libraries can be brought onto the new pipeline without re-transcribing.
- **`Library` Ruby class** at `skills/buttercut-lib/library.rb`. Centralizes every read and write of `library.yaml` behind one API — `summary`, `ready?`, `recent`, `add_videos`, `complete`, `video_record`, and friends. Skills no longer parse the YAML inline; the orchestrator calls `Library` and sub-agents stay out of the file entirely, removing a class of race-condition bugs. Also exposes a CLI (`ruby skills/buttercut-lib/library.rb <name> <command>`) so skill prompts can ask for library state in one line.

### Changed
- **`roughcut` skill renamed to `cut`.** The skill now branches across scene, selects, custom, and roughcut task types up front instead of treating every cut as a roughcut. Output directory follows suit: each library's `roughcuts/` is now `cuts/`. Existing libraries migrate with `ruby scripts/004_migrate_roughcuts_to_cuts.rb --all` (renames the folder; merges into an existing `cuts/` and refuses on filename conflicts).
- **Footage analysis is dramatically faster.** Visual transcripts (LLM-driven, frame-by-frame) are gone. Each clip now gets a contact sheet (a single image grid covering the whole clip with timestamps burned in) and the existing markdown summary. Contact sheet generation is pure ffmpeg — no LLM in that step — so analysis runtime drops from roughly 1× footage length to a small fraction of it. The roughcut agent reads the contact sheet to "see" a clip at a glance, extracts dialogue from the audio transcript on demand via `script_extractor.rb`, and greps the transcript JSON for word-level cut timing.
- **`summarize-video` skill folded into `analyze-video`.** One skill, one parent dispatch, one sub-agent per clip.
- **New `contact_sheet_job.rb` orchestrator.** Takes a library name plus an explicit list of clip filenames; generates `_full.jpg` for each (plus 10-minute chunk sheets for clips longer than 10 minutes) and updates library.yaml. Always rebuilds for the clips it's given. Single-threaded by design — the parent agent decides how many invocations to run in parallel based on machine headroom.
- **Clean dialogue is extracted on demand, not pre-baked.** `script_extractor.rb` reads an audio transcript JSON and prints clean dialogue (one segment per line, no timing) to stdout. The roughcut and analyze-video sub-agents call it when they need words; nothing is written to disk. The transcript JSON stays the single source of truth, so refinement edits never get out of sync with a cached script.
- **Analyze-video sub-agents now write each summary in one shot.** The four-placeholder skeleton + four-Edit dance is gone; the sub-agent reads the contact sheet, extracts dialogue via `script_extractor.rb`, and issues a single `Write` with the full markdown. Drops per-clip from 7 tool calls to 3 — roughly halves the slowest-batch wall.
- **Library schema:** new `contact_sheet:` field per video; `visual_transcript:` is deprecated. Old libraries keep their `visual_*.json` files on disk — no migration runs. Re-run analysis on an old library to populate the new field.
- **Skills moved to top-level `skills/`.** Shipped skills now live in `skills/` so Claude Code, Codex, and other agentic CLIs that read `skills/` natively all find the same files. `.claude/skills` is a git-tracked symlink pointing to `../skills`, so Claude Code keeps working unchanged. On a fresh clone this is automatic; if you're updating an old install via `update-buttercut`'s rsync path (no git), you may need to delete the old `.claude/skills/` directory once so the symlink can take its place.
- **Project instructions moved to `AGENTS.md`.** `CLAUDE.md` is now a one-line `@AGENTS.md` import, so non-Claude agents that read `AGENTS.md` by convention pick up the same rules.
- **Library backups now live outside ButterCut.** Default backup directory is `~/Documents/buttercut-video-editor-backups` instead of an inside ButterCut folder. Backups are now also saved by individual library.
- **`backup-library` skill now uses Apple Archive (`aa`)** instead of `zip`, producing smaller archives and faster restores on macOS.
- **Contact sheets require ffmpeg with `drawtext` support.** Setup verifies this; without it, timestamps can't be burned into the grid frames.
- **License switched to PolyForm Noncommercial 1.0.0**, with a carve-out that explicitly permits commercial use of any video you produce with ButterCut. The tool itself is free for personal, evaluation, and noncommercial use; commercial use of the tool requires a separate license. Edit, sell, and distribute the videos you make with it freely.
- **Setup uses precompiled Ruby and Python binaries via mise**, so first-run install no longer waits on local compilation. New machines reach a working ButterCut in minutes instead of the long compile cycle the previous setup required.
- **B-roll clips with no dialogue are handled gracefully.** Earlier versions could trip when the cut included a clip whose transcript was empty; the cut skill now treats those clips as visual-only and slots them in without trying to time edits against missing words.

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
