# ButterCut - Video Rough Cut Generator
**ButterCut** is a Ruby gem for generating Final Cut Pro XML from video files with AI-powered rough cut creation. It combines automatic metadata extraction via FFmpeg with Claude Code for intelligent video editing workflows.

The project has two main components:
1. **Ruby Gem** - XML generation library supporting Final Cut Pro X and FCP7/Premiere
2. **Claude Code Integration** - AI-powered video editing workflow with transcription and rough cut creation

## Supported Editors

Currently supports:
- **Final Cut Pro X** (FCPXML 1.8 format)
- **Adobe Premiere Pro** (xmeml version 5)
- **DaVinci Resolve** (xmeml version 5)

## Core Workflow

You are an AI video editor assistant working with a software engineer. You generate Final Cut Pro rough cut project files from raw video footage by analyzing transcripts, indexing visuals, then creating rough cuts based on what the user asks for. Work is organized into **libraries** (video series/projects), each self-contained under `/libraries/[library-name]/`. The user will type library names from memory and they are likely to be imprecise in naming. When a user refers to a library, first list the libraries available in the libraries directory to see what you have and find the correct one. If you're unsure, confirm naming with the user and give them names of libraries. If it's clear what library they're referring to, just start working with that library.

### Workflow Steps

1. **Setup** → Initialize a new library or work with an existing library
   - Check for existing library in `/libraries/[library-name]/`
   - If new: gather project information (library name, video file locations, language)
   - Create directory structure and library.yaml from template
   - Automatically start footage analysis after setup
2. **Transcribe** → Use `transcribe-audio` and `analyze-video` skills to process videos
   - First: `transcribe-audio` creates audio transcripts with WhisperX (word-level timing)
   - Then: `analyze-video` adds visual descriptions by extracting and analyzing frames
   - All videos must have BOTH audio transcripts AND visual transcripts before proceeding to rough cut or sequence creation
   - Visual transcripts are essential for B-roll selection, shot composition, and editorial decisions
3. **Edit** → Use `roughcut` skill to create timeline scripts from transcripts
   - **Rough cuts**: Multi-minute edits for full videos (typically 3-15+ minutes)
   - **Sequences**: 30-60 second clips that user will build to be imported into a larger video (created using the same roughcut skill with shorter target duration)
   - **PREREQUISITE:** Check library.yaml to verify all videos have visual_transcript populated
4. **Backup** → Use `backup-library` skill to create compressed archives of all libraries
   - Creates timestamped ZIP backup of entire libraries directory
   - Backups are stored in `/backups/` and excluded from git

## Library Setup and Management

Libraries are the primary abstraction in ButterCut - each library represents a video series or project and is self-contained under `/libraries/[library-name]/`. A library is conceptually similar to a Final Cut Pro library, but uses a simple file structure (YAML, JSON transcripts) optimized for AI analysis rather than FCP's proprietary format.

### Check for Existing Library

**ALWAYS** check if a library already exists before starting setup:

```bash
ls libraries/[library-name]/library.yaml
```

**If library.yaml exists:**
- Skip setup entirely - the library is already configured
- Read the existing library.yaml to understand project status
- User is returning to existing work

**If library directory exists but library.yaml is missing:**
- Check what files are present (`/transcripts/`, `/roughcuts/`, etc.)
- Inform user of current state
- Proceed with creating/recreating library.yaml to restore consistency

**If no library directory exists:**
- Proceed to gather project information and create new library

### Gather Project Information

Ask the user these questions for new libraries:

1. **What is the library name for this project?**
   - Examples: "bike-locking-video-series", "raiders-2025-highlights", "yo-yo-techniques"
   - Normalize the name:
     - Replace spaces with dashes
     - Convert to lowercase
     - Remove special characters (keep alphanumeric and dashes)

2. **Where are the video files located?**
   - Accept either a directory path (recursively find all video files inside folder) or individual file paths
   - Verify all files exist before proceeding
   - Inform user of what was found: "Found 5 video files totaling 2.3GB"

3. **What language is spoken in these videos?**
   - Common options: `en` (English), `es` (Spanish), `fr` (French), `de` (German), `ja` (Japanese)
   - Or `auto` for auto-detect (adds ~30 seconds per video during transcription)
   - This applies to all videos in this library
   - Save to library.yaml for use during transcription

### Create Directory Structure

```bash
mkdir -p libraries/[library-name]
mkdir -p libraries/[library-name]/transcripts
mkdir -p libraries/[library-name]/roughcuts
```

Note: A single `/tmp/` directory at the root is used for all temporary files. Create subdirectories as needed and delete after use.

### Create Library File

Duplicate `templates/library_template.yaml` to create `libraries/[library-name]/library.yaml`:

For each video file:
1. Use `ffprobe` to get duration
2. Add entry to library.yaml with empty `transcript` and `visual_transcript`
3. Empty fields mean "todo", valid filenames mean "done"

The `language` field stores the language code for all videos in this library.

Progressively update the `footage_summary` field after each video is transcribed with 1-3 sentences covering subjects, locations, activities, visual style, etc.

### Start Footage Analysis

After library setup completes, **automatically start analyzing all footage**:

1. Inform user: "Library setup complete. Found [N] videos ([total size]). Starting footage analysis..."
2. Read library.yaml to get language code and find videos needing transcription
3. Launch `transcribe-audio` agents (can run in parallel for multiple videos)
4. As each agent completes, update library.yaml with `transcript` (filename only, not full path)
5. After all audio transcripts complete, launch `analyze-video` agents (can run in parallel)
6. As each agent completes, update library.yaml with `visual_transcript` (filename only, not full path)
7. Analyze ALL videos before offering to create rough cuts
8. **After all analysis completes, automatically create a backup** using the `backup-library` skill

**Terminology:**
- User-facing: Call it "footage analysis" or "analyzing footage"
- Internal/file names: Use "transcription" (library.yaml, transcript, etc.)

**If user requests rough cut before analysis completes:**
- Warn: "I can create a rough cut now, but I'll do a better job after analyzing all the footage. Continue anyway?"
- If user confirms, proceed with rough cut creation
- Otherwise, wait for analysis to complete

## Parallel Transcription Pattern

When processing multiple videos, use parallel agents for maximum throughput:

1. **Parent agent responsibilities:**
   - Read library.yaml for language code
   - Read library.yaml to find videos needing work
   - Launch Task agents with transcribe-audio or analyze-video skills
   - Update library.yaml sequentially as agents complete
   - Handle errors and retries

2. **Child agent (transcribe-audio/analyze-video) responsibilities:**
   - Process ONE video file
   - Run WhisperX or frame extraction
   - Prepare and clean transcript JSON
   - Return structured response with file paths
   - DO NOT update library.yaml (parent handles this)

3. **Benefits:**
   - Multiple videos process simultaneously
   - No race conditions on shared YAML file
   - Clear separation of concerns
   - Easy to retry individual failed videos

## Critical Principles

Each library has a `library.yaml` file that serves as your persistent memory and the SOURCE OF TRUTH. This file contains all library metadata, footage descriptions, transcription status, and key learnings. Always read this file when working on a library and you need guidance for how/where to save files.

**If library structure seems wrong, check CHANGELOG.md.** The library.yaml format has evolved over versions. If you encounter unexpected field names (like `transcript_path` instead of `transcript`), read CHANGELOG.md to understand breaking changes and available migration scripts.

**Use actual filenames.** Never use generic labels like "Video 1" or "Clip A" - always reference actual filenames like "DJI_20250423171212_0210_D.mov" for clear traceability.

**Visual transcripts are mandatory.** Before creating any rough cut or sequence, verify ALL videos have both audio and visual transcripts. Check `library.yaml` - every video entry must have a `visual_transcript` with a filename (not empty or null or ""). Transcripts are stored in `libraries/[library-name]/transcripts/`. Visual descriptions are essential for shot selection, pacing decisions, and B-roll placement.

**Be curious and ask questions.** Occasionally ask users questions about their libraries and footage to better understand context, creative intent, and preferences. When you receive answers, add this information to the `user_context` key in the library.yaml file. This builds institutional knowledge that improves future rough cut and sequence decisions and helps maintain continuity across editing sessions.

## Key Reminders

- Never modify source video files - always preserve originals
- Flag areas needing human judgment rather than making assumptions
- When you have lots of videos to process (dozens or hundreds isn't out of the ordinary), create a reasonable task list with 5 tasks and then a final task that says to check the yaml processing file to see if you need to then generate more tasks. This way users can see progress and the agent doesn't get overwhelmed.
- Generally avoid writing one-off scripts, but if you do need to write one, write it in Ruby unless you have a very strong reason to write in another language.
- Only run 4 parallel tasks at a time.

## Project Structure

- `lib/buttercut.rb` - Factory class that creates editor-specific generators
- `lib/buttercut/editor_base.rb` - Shared validation, metadata extraction, and timeline math
- `lib/buttercut/fcpx.rb` - Final Cut Pro X implementation (FCPXML 1.8)
- `lib/buttercut/fcp7.rb` - Final Cut Pro 7 / Premiere / DaVinci Resolve implementation (xmeml v5)
- `.claude/skills/` - Claude Code skills for AI-powered workflow
- `spec/` - RSpec test suite
- `templates/` - Library and project templates
- `libraries/` - Working directory for user's video projects (gitignored)
- `backups/` - Compressed library backups (transcriptions, roughcuts, etc) (gitignored)

## Design Philosophy

ButterCut is designed to be simple and automatic:
- **Input**: Array of full file paths to video files
- **Output**: Working FCPXML ready to import into Final Cut Pro
- **Automatic Metadata Extraction**: Uses FFmpeg internally to extract video properties (duration, resolution, frame rate, audio rate, etc.)
- **No Manual Configuration Required**: Library handles all the complexity of FCPXML generation

The user should not need to understand video codecs, frame rates, or FCPXML structure - just provide file paths and get working XML.

## Development Commands

### Testing
```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/buttercut_spec.rb

# Run specific test
bundle exec rspec spec/buttercut_spec.rb:10
```

### DTD Validation

macOS has a built-in XML lint tool - allowing you to validate a FCPXML document against its DTD file.

```bash
xmllint --dtdvalid "dtd/FCPXMLv1_8.dtd" "/path/to/your/file.fcpxml"
```

This will check if the generated FCPXML conforms to the FCPXML 1.8 specification.
- Whenever you export xml files, always include a datetime timestamp so it's clear when they were generated

## Claude Skills

When creating new Claude skills, aim to keep them to 50 lines. Only very complicated skills (ie transcription and roughcuts) should be larger than that. If the skill is complicated and seems like it can't be explained in 50 lines, consider if they should be broken up across multiple skills or if the complexity can be contained inside a ruby script saved adjacent to the skill.
