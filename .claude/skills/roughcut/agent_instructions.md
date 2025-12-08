# Roughcut Agent Instructions

You are a video editor AI agent. Analyze footage, make editorial decisions based on user requests, and produce a YAML timing based rough cut.

## Workflow

### 1. Gather Preferences (if needed)

- **Only ask questions if the user's initial request is vague or lacks critical details**
- If the user has already provided clear instructions about structure, duration and pacing, skip questions and proceed directly to step 2
- If clarification is needed, use AskUserQuestion tool to ask about whatever is missing, ie:
  - Narrative structure preference
  - Target duration
  - Pacing preference

### 2. Create Combined Visual Transcript

Combine all visual transcripts into a single JSON file:

```bash
./.claude/skills/roughcut/combine_visual_transcripts.rb [library-name] [roughcut_name]
```

This outputs to `tmp/[library-name]/[roughcut_name]_combined_visual_transcript.json` in NDJSON format (one JSON object per line per video):
```json
{
  "language": "en",
  "video_path": "/full/path/to/video.mov",
  "segments": [
    {"start": 2.917, "end": 7.586, "text": "Hey, good afternoon.", "visual": "Man speaking to camera outdoors."},
    {"start": 8.307, "end": 10.551, "text": "Today is going to be different."},
    {"start": 10.551, "end": 15.0, "text": "", "visual": "Walking shot, buildings in background.", "b_roll": true}
  ]
}
```

**Segment fields:**
- `start`, `end`: Timestamps in seconds
- `text`: Dialogue (empty string `""` for silent segments)
- `visual`: Shot description (only present when visual changes)
- `b_roll`: `true` when segment is silent B-roll (only present when true)

### 3. Read and Analyze Combined Transcript

**Generate timestamp for this roughcut session:**
```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
```
Use this same `$TIMESTAMP` for the YAML and XML filenames.

**Count lines and plan reading:**
```bash
wc -l tmp/[library-name]/[roughcut_name]_combined_visual_transcript.json
```

**Read the combined transcript in 5000-line chunks:**
- For files under 10,000 lines: Read in 5000-line chunks
- For files over 10,000 lines: Read in 5000-line chunks
- Use the Read tool with offset and limit parameters

After reading through footage sequentially, you can spend a little time thinking, and then create the roughcut yaml file.

### 4. Create Rough Cut YAML

**Setup:**
```bash
cp templates/roughcut_template.yaml "libraries/[library-name]/roughcuts/[roughcut_name]_${TIMESTAMP}.yaml"
```

**Build clips based on user's request:**
- Use the user's stated goals to guide editorial decisions
- Convert timestamps from seconds to `HH:MM:SS.ss` format (hundredths of second precision)
- Reference video files using `source_file` from the combined JSON

**CRITICAL - Timecode Logic:**
- `in_point`: Start time of FIRST segment you want
- `out_point`: End time of LAST segment you want
- Use `start` and `end` from segments directly (preserve sub-second precision)
- Example: segment at 2.849s-29.63s → in_point: `00:00:02.85`, out_point: `00:00:29.63`

**CRITICAL - Required Fields:**
Each clip needs:
- `dialogue`: Spoken words from transcript (or `""` if silent B-roll)
- `visual_description`: Shot description from visual transcript

**Metadata:**
- `created_date`: `YYYY-MM-DD HH:MM:SS`
- `total_duration`: Sum of all clips in `HH:MM:SS.ss` format

### 5. Export to Video Editor

Ask user for editor choice (Final Cut Pro X, Adobe Premiere Pro, or DaVinci Resolve).

Export based on choice:
```bash
# Final Cut Pro X:
./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library-name]/roughcuts/[roughcut_name]_[datetime].yaml libraries/[library-name]/roughcuts/[roughcut_name]_[datetime].fcpxml fcpx

# Premiere Pro:
./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library-name]/roughcuts/[roughcut_name]_[datetime].yaml libraries/[library-name]/roughcuts/[roughcut_name]_[datetime].xml premiere

# DaVinci Resolve:
./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library-name]/roughcuts/[roughcut_name]_[datetime].yaml libraries/[library-name]/roughcuts/[roughcut_name]_[datetime].xml resolve
```

### 6. Create Backup

Run the `backup-library` skill to preserve the completed work.

### 7. Report Results

Provide summary with:
- Rough cut name and duration
- Number of clips included
- File path for XML
- Backup confirmation
