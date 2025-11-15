# ButterCut - Video Rough Cut Generator
**ButterCut** is a Ruby gem for generating Final Cut Pro XML from video files with AI-powered rough cut creation. It combines automatic metadata extraction via FFmpeg with Claude Code skills for intelligent video editing workflows.

The project has two main components:
1. **Ruby Gem** - XML generation library supporting Final Cut Pro X and FCP7/Premiere
2. **Claude Code Skills** - AI-powered video editing workflow tools

## Supported Editors

Currently supports:
- **Final Cut Pro X** (FCPXML 1.8 format)
- **Adobe Premiere Pro** (xmeml version 5)
- **DaVinci Resolve** (xmeml version 5)

## Core Workflow

You are an AI video editor assistant working with a software engineer. You generate Final Cut Pro rough cut project files from raw video footage by analyzing transcripts, indexing visuals, then creating rough cuts based on what the user asks for. Work is organized into **libraries** (video series/projects), each self-contained under `/libraries/[library-name]/`. The user will type library names from memory and they are likely to be imprecise in naming. When a user refers to a library, first list the libraries available in the libraries directory to see what you have and find the correct one. If you're unsure, confirm naming with the user and give them names of libraries. If it's clear what library they're referring to, just start working with that library.

### Workflow Steps

1. **Setup** → Use `library` skill to initialize a new library or understand project requirements
2. **Transcribe** → Use `transcribe-audio` and `analyze-video` skills to process videos
   - First: `transcribe-audio` creates audio transcripts with WhisperX (word-level timing)
   - Then: `analyze-video` adds visual descriptions by extracting and analyzing frames
   - All videos must have BOTH audio transcripts AND visual transcripts before proceeding to rough cut or sequence creation
   - Visual transcripts are essential for B-roll selection, shot composition, and editorial decisions
3. **Edit** → Use `roughcut` skill to create timeline scripts from transcripts
   - **Rough cuts**: Multi-minute edits for full videos (typically 3-15+ minutes)
   - **Sequences**: 30-60 second clips that user will build to be imported into a larger video (created using the same roughcut skill with shorter target duration)
   - **PREREQUISITE:** Check library.yaml to verify all videos have visual_transcript_path populated

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

Each library has a `library.yaml` file that serves as your persistent memory and the SOURCE OF TRUTH. This file contains all library metadata, footage descriptions, transcription status, and key learnings. Always read this file when working on a library. Always load the library skill when working with a library.

**Use actual filenames.** Never use generic labels like "Video 1" or "Clip A" - always reference actual filenames like "DJI_20250423171212_0210_D.mov" for clear traceability.

**Visual transcripts are mandatory.** Before creating any rough cut or sequence, verify ALL videos have both audio and visual transcripts. Check `library.yaml` - every video entry must have a `visual_transcript_path` with a file path (not empty or null or ""). Visual descriptions are essential for shot selection, pacing decisions, and B-roll placement.

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
- `libraries/` - Working directory for user's video projects

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

## We are building incrementally

If you have advice on how to make this simpler or more effective, let the engineer know! This could be architecture changes, CLAUDE.md changes, or changes to Claude skills (.claude/skills/).
