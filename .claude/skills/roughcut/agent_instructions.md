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

Combine all visual transcripts into a single file:

```bash
mkdir -p tmp/[library-name] && cat libraries/[library-name]/transcripts/visual_*.json > tmp/[library-name]/[roughcut_name]_combined_visual_transcript.json
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

**Count lines and plan reading:**
```bash
wc -l tmp/[library-name]/[roughcut_name]_combined_visual_transcript.json
```

**Read the combined transcript in 5000-line chunks** using the Read tool with offset and limit parameters.

After reading through footage sequentially, you can spend a little time thinking, and then create the roughcut yaml file.

### 4. Create Rough Cut YAML

**Generate a timestamp** using `date +%Y%m%d_%H%M%S` and use the resulting value as a literal string in all filenames for this roughcut session (YAML and XML).

**Setup:**
```bash
cp templates/roughcut_template.yaml "libraries/[library-name]/roughcuts/[roughcut_name]_[timestamp].yaml"
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

Check `library.yaml` for the `editor` field. If it's set, use that value. If it's not set or empty, ask the user for their editor choice (Final Cut Pro X, Adobe Premiere Pro, or DaVinci Resolve), then save their choice back to `library.yaml` (`fcpx`, `premiere`, or `resolve`).

**Export command syntax:**
```bash
bundle exec ./.claude/skills/roughcut/export_to_fcpxml.rb <roughcut.yaml> <output.xml> [editor] [fps] [width] [height] [options]
```

**Options:**
- `editor`: `fcpx` (default), `premiere`, or `resolve`
- `fps`: Override sequence frame rate (e.g., `50` for 50fps)
- `width height`: Custom sequence dimensions (e.g., `1080 1920` for portrait/vertical video)
- `--windows-file-paths`: Convert Linux paths to Windows format (use when running in WSL and editing on Windows)
- `--audio <file>`: Add audio/music track to sequence (automatically trimmed to fit sequence duration)

**Detect WSL environment:**
```bash
# Check if running in WSL (paths start with /mnt/)
if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
  echo "Running in WSL - use --windows-file-paths for Premiere/Resolve on Windows"
fi
```

**Export examples:**
```bash
# Final Cut Pro X (standard):
bundle exec ./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library]/roughcuts/[name].yaml libraries/[library]/roughcuts/[name].fcpxml fcpx

# Premiere Pro (standard landscape):
bundle exec ./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library]/roughcuts/[name].yaml libraries/[library]/roughcuts/[name].xml premiere

# Premiere Pro (portrait 1080x1920 at 50fps, WSL to Windows paths):
bundle exec ./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library]/roughcuts/[name].yaml libraries/[library]/roughcuts/[name].xml premiere 50 1080 1920 --windows-file-paths

# With music track (audio trimmed to sequence length):
bundle exec ./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library]/roughcuts/[name].yaml libraries/[library]/roughcuts/[name].xml premiere 50 1080 1920 --windows-file-paths --audio /path/to/music.mp3

# DaVinci Resolve:
bundle exec ./.claude/skills/roughcut/export_to_fcpxml.rb libraries/[library]/roughcuts/[name].yaml libraries/[library]/roughcuts/[name].xml resolve
```

### 6. Create Backup

Run the `backup-library` skill to preserve the completed work.

### 7. Report Results

Provide summary with:
- Rough cut name and duration
- Number of clips included
- File path for XML
- Backup confirmation
