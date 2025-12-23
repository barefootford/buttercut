---
name: analyze-video
description: Adds visual descriptions to transcripts by extracting and analyzing video frames with ffmpeg. Creates visual transcript with a visual description of the video clip. Use when all files have audio transcripts present (transcript) but don't yet have visual transcripts created (visual_transcript).
---

# Skill: Analyze Video

Add visual descriptions to audio transcripts by extracting JPG frames with ffmpeg and analyzing them. **Never read video files directly** - extract frames first.

## Prerequisites

Videos must have audio transcripts. Run **transcribe-audio** skill first if needed.

## Workflow

### 1. Copy & Clean Audio Transcript

Don't read the audio transcript, just copy it and then prepare it by using the prepare_visual_script.rb file. This removes word-level timing data and prettifies the JSON for easier editing:

```bash
cp libraries/[library]/transcripts/video.json libraries/[library]/transcripts/visual_video.json
ruby .claude/skills/analyze-video/prepare_visual_script.rb libraries/[library]/transcripts/visual_video.json
```

### 2. Extract Frames

Create frame directory and extract 2 frames from the beginning of the video:

```bash
mkdir -p tmp/frames/[video_name]
ffmpeg -ss 00:00:01 -i video.mov -vframes 1 -vf "scale=1280:-1" tmp/frames/[video_name]/frame_1s.jpg
ffmpeg -ss 00:00:05 -i video.mov -vframes 1 -vf "scale=1280:-1" tmp/frames/[video_name]/frame_5s.jpg
```

For very short videos (<5s), just extract the 1s frame.

### 3. Add Visual Description

Read the visual video json file that you created earlier.

**Read the JPG frames** from `tmp/frames/[video_name]/` using Read tool, then **Edit** `visual_video.json` to add a `visual` field to the **first segment only**:

```json
{
  "start": 2.917,
  "end": 7.586,
  "text": "Hey, good afternoon everybody.",
  "visual": "Man in red shirt speaking to camera in medium shot. Home office with bookshelf. Natural lighting.",
  "words": [...]
}
```

**For B-roll clips** (no dialogue), add a single segment:
```json
{
  "start": 0.0,
  "end": 10.5,
  "text": "",
  "visual": "Green bicycle parked in front of building. Urban street with trees.",
  "b_roll": true,
  "words": []
}
```

**Guidelines:**
- One visual description per video (on the first segment)
- 2-3 sentences: subject, setting, shot type, lighting
- Assume the shot stays consistent throughout the clip

### 4. Cleanup & Return

```bash
rm -rf tmp/frames/[video_name]
```

Return structured response:
```
✓ [video_filename.mov] analyzed successfully
  Visual transcript: libraries/[library]/transcripts/visual_video.json
  Video path: /full/path/to/video_filename.mov
```

**DO NOT update library.yaml** - parent agent handles this to avoid race conditions in parallel execution.
