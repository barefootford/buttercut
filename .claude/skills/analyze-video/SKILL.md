---
name: analyze-video
description: Adds visual descriptions to transcripts by extracting and analyzing video frames with ffmpeg. Creates visual transcript with periodic visual descriptions of the video clip. Use when all files have audio transcripts present (transcript) but don't yet have visual transcripts created (visual_transcript).
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

### 2. Extract Frames (Binary Search)

Create frame directory: `mkdir -p tmp/frames/[video_name]`

**Videos ≤30s:** Extract one frame at 2s
**Videos >30s:** Extract start (2s), middle (duration/2), end (duration-2s)

```bash
ffmpeg -ss 00:00:02 -i video.mov -vframes 1 -vf "scale=1280:-1" tmp/frames/[video_name]/start.jpg
```

**Subdivide when:** Footage start, middle and end have different subjects, setting or angle changes
**Stop when:** The footage no longer seems to be changing or only has minor changes
**Never sample** more frequently than once per 30 seconds

### 3. Add Visual Descriptions

Read the visual video json file that you created earlier.

**Read the JPG frames** from `tmp/frames/[video_name]/` using Read tool, then **Edit** `visual_video.json`:

Do these incrementally. You don't need to create a program or script to do this, just incrementally edit the json whenever you read new frames.

**Dialogue segments - add `visual` field:**
```json
{
  "start": 2.917,
  "end": 7.586,
  "text": "Hey, good afternoon everybody.",
  "visual": "Man in red shirt speaking to camera in medium shot. Home office with bookshelf. Natural lighting.",
  "words": [...]
}
```

**B-roll segments - insert new entries:**
```json
{
  "start": 35.474,
  "end": 56.162,
  "text": "",
  "visual": "Green bicycle parked in front of building. Urban street with trees.",
  "b_roll": true,
  "words": []
}
```

**Guidelines:**
- Descriptions should be 3 sentences max.
- First segment: detailed (subject, setting, shot type, lighting, camera style)
- Continuing shots: brief if similar, otherwise can be up to 3 sentences if drastically different.

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
