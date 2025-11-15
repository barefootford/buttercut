---
name: roughcut
description: Creates video rough cut yaml file for use with Buttercut gem. Concatenates visual transcripts with file markers, creates a roughcut yaml with clip selections, then exports to XML format. Use this skill when users want a "roughcut", "sequence" or "scene" generated. These are all the same thing, just with different lengths.
---

# Skill: Create Rough Cut

This skill handles the editorial process of creating rough cut timeline scripts from transcribed video footage. It analyzes transcripts, makes editorial decisions, outputs a structured YAML rough cut, and exports it to Final Cut Pro XML format.

**Note:** This skill is used for both full-length rough cuts (3-15+ minutes) and short sequences (30-60 seconds). When the user asks for a "sequence", use this skill with a target duration of 30-60 seconds.

## Prerequisites

### Transcript Verification
- Check `libraries/[library-name]/library.yaml`
- Every video must have both `transcript_path` and `visual_transcript_path` populated
- If any visual transcripts are missing, inform user that transcript processing must be completed first and ask them if they want claude to finish transcript processing

### Project Context
- Read `libraries/[library-name]/library.yaml` for footage overview and metadata

## Rough Cuts vs Sequences

This skill creates both full-length rough cuts (3-15+ minutes) and short sequences (30-60 seconds for social media/teasers). When creating sequences, prioritize impact over completeness with fast-paced editing and ruthless cuts to stay within the 60-second maximum.

## Implementation Steps

### 1. Determine Rough Cut Name
- Create a name based off what the user said the rough cut should be about.
- Include the datetime in the filename in case the user wants revisions
- Examples: "ruby_meetup_intro_datetime", "day_in_life_datetime", "product_demo_datetime"

### 2. Create Combined Visual Transcript
- Run the combine script to create a single JSON file with all visual transcripts:
```bash
./.claude/skills/roughcut/combine_visual_transcripts.rb [library-name] [roughcut_name]
```

**What this script does:**
- Finds all `visual_*.json` files in `libraries/[library-name]/transcripts/`
- Combines them into a single file with source file metadata
- Each video's segments are preserved with their source information
- Outputs to `/tmp/[library-name]/[roughcut_name]_combined_visual_transcript.json`

**Example output format:**
```json
[
  {
    "source_file": "DJI_20250423171212_0210_D.mov",
    "video_path": "/Users/andrew/code/video-agent/media/DJI_20250423171212_0210_D.mov",
    "segments": [
      {
        "start": 2.917,
        "end": 7.586,
        "text": "Hey, good afternoon everybody.",
        "visual": "Man speaking to camera outdoors..."
      },
      {
        "start": 8.307,
        "end": 10.551,
        "text": "Today is going to be a little bit different than normal."
      }
    ]
  },
  {
    "source_file": "DJI_20250423171409_0211_D.mov",
    "video_path": "/Users/andrew/code/video-agent/media/DJI_20250423171409_0211_D.mov",
    "segments": [...]
  }
]
```

- Script output location: `/tmp/[library-name]/[roughcut_name]_combined_visual_transcript.json`
- Previous combined transcripts are kept temporarily (replaced on next rough cut creation)

### 3. Analyze Footage and Gather User Preferences

**Read and Analyze:**
- Read the entire combined visual transcript JSON file, if possible.
- The file may be very large depending on the amount of footage. If it's too large, read it in chunks, creating your roughcut incrementally. Adding and removing clips as you read different parts of the combined visual transcript.
- Study the footage deeply - understand what story elements you have
- Identify narrative threads, emotional beats, and visual opportunities
- Track which segments come from which source files using the `source_file` field in each video object

**Interactive User Consultation:**
After analyzing the footage, use the AskUserQuestion tool to ask 3 questions about their rough cut preferences. Ask questions like this, but custom tailored to their video footage:
- Narrative structure (chronological, thematic, or hook-based opening)
- Target duration (1 minute, 5 minute, 10 minute, etc)
- Pacing (Faster cuts, slower cuts, etc)

### 4. Create Rough Cut from Combined Transcript - THE CORE EDITORIAL PROCESS

This is the creative heart of the video agent - transforming raw footage into a coherent story based on user preferences.

**Think Through the Edit:**
Using the user's preferences as your guide, consider:
- What's the most compelling way to tell this story given their goals?
- What order creates the best narrative flow for their chosen structure?
- Where do you need B-roll for pacing and visual interest?
- What can be cut to improve the overall piece while meeting duration targets?
- For multiple takes: select the best take and move forward
- For B-roll: use each timestamp only once per rough cut (no repeating moments)

**Create the Rough Cut:**
- Copy template: `cp templates/roughcut_template.yaml libraries/[library-name]/roughcuts/[roughcut_name]_datetime1.yaml`
- Build your clips array thoughtfully - each clip should serve a purpose
- Use timestamps from the JSON segments (in seconds) and convert to `HH:MM:SS` format (round to nearest second)
- Use the `source_file` field from the combined JSON to identify which video file each clip comes from
- **CRITICAL - Timecode Logic**:
  - `in_point`: Use the `start` time of the FIRST segment you want to include
  - `out_point`: Use the `end` time of the LAST segment you want to include
  - This ensures the full dialogue is included in the clip (not cut off mid-sentence)
  - Example: If you want segments starting at 2.849s and 15.008s-29.63s, use in_point: 00:00:02, out_point: 00:00:29
- **CRITICAL**: Each clip must include BOTH fields (inferred from visual transcripts):
  - `dialogue`: The actual spoken words from the transcript (or empty string "" if silent B-roll)
  - `visual_description`: Shot description from visual transcript (e.g., "[Wide shot of ruby meetup, programmers at desks with laptops]")
  - This makes the YAML completely readable as a standalone document showing exactly what's on screen and what's being said

**Populate Metadata:**
- Set `created_date` in format: `2025-04-23 14:30:22`
- Calculate `total_duration` from all clips in `HH:MM:SS` format
- Example: if clips total 1 hour, 23 minutes, 45 seconds → `01:23:45`

**Review and Validate:**
- Verify all source files referenced exist in library.yaml
- Ensure timecodes are logically within source video durations
- Confirm the narrative flow makes sense
- Trust your judgment - you're the editor making something watchable

### 5. Export to Video Editor XML

**Ask User for Editor Preference:**
- Use the AskUserQuestion tool to ask which video editor they want to use
- Provide three options:
  - **Final Cut Pro X**: Uses FCPXML 1.8 format (`.fcpxml` extension)
  - **Adobe Premiere Pro**: Uses xmeml version 5 format (`.xml` extension)
  - **DaVinci Resolve**: Uses xmeml version 5 format (`.xml` extension)

**Export Based on Editor Choice:**
- After creating the YAML rough cut, immediately export to the appropriate format
- Run the export script with the editor parameter:
```bash
# For Final Cut Pro X:
./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library-name]/roughcuts/[roughcut_name]_datetime1.yaml libraries/[library-name]/roughcuts/[roughcut_name]_datetime1.fcpxml fcpx

# For Adobe Premiere Pro:
./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library-name]/roughcuts/[roughcut_name]_datetime1.yaml libraries/[library-name]/roughcuts/[roughcut_name]_datetime1.xml premiere

# For DaVinci Resolve:
./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library-name]/roughcuts/[roughcut_name]_datetime1.yaml libraries/[library-name]/roughcuts/[roughcut_name]_datetime1.xml resolve
```
