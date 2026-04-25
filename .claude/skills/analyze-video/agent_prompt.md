# Analyze Video (sub-agent prompt)

You are a sub-agent. Add visual descriptions to one video's audio transcript by extracting JPG frames with ffmpeg and analyzing them. **Never read the video file directly** — extract frames first.

## Inputs (passed inline by the parent)

- `video_path` — absolute path to the video file
- `audio_transcript_path` — absolute path to the prepared audio transcript JSON
- `visual_transcript_path` — absolute path to write the visual transcript JSON

Do NOT read `library.yaml` or `settings.yaml`.

## 1. Copy & clean audio transcript

Don't read the audio transcript — just copy it, then prepare it via `prepare_visual_script.rb`. This removes word-level timing data and prettifies the JSON for easier editing:

```bash
cp <audio_transcript_path> <visual_transcript_path>
ruby .claude/skills/analyze-video/prepare_visual_script.rb <visual_transcript_path>
```

## 2. Extract frames (binary search)

Create frame directory: `mkdir -p tmp/frames/[video_name]`

**Videos ≤30s:** extract one frame at 2s
**Videos >30s:** extract start (2s), middle (duration/2), end (duration-2s)

```bash
ffmpeg -ss 00:00:02 -i video.mov -vframes 1 -vf "scale=1280:-1" tmp/frames/[video_name]/start.jpg
```

**Subdivide when:** start, middle, and end have different subjects, settings, or angle changes
**Stop when:** the footage no longer seems to be changing or only has minor changes
**Never sample** more frequently than once per 30 seconds

## 3. Add visual descriptions

Read the visual transcript JSON you created in step 1.

**Read the JPG frames** from `tmp/frames/[video_name]/` using the Read tool, then **Edit** the file at `<visual_transcript_path>`. Do this incrementally — no script needed; just edit the JSON each time you read new frames.

**Dialogue segments — add `visual` field:**
```json
{
  "start": 2.917,
  "end": 7.586,
  "text": "Hey, good afternoon everybody.",
  "visual": "Man in red shirt speaking to camera in medium shot. Home office with bookshelf. Natural lighting.",
  "words": [...]
}
```

**B-roll segments — insert new entries:**
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
- Descriptions: 3 sentences max
- First segment: detailed (subject, setting, shot type, lighting, camera style)
- Continuing shots: brief if similar; up to 3 sentences if drastically different

## 4. Cleanup & return

```bash
rm -rf tmp/frames/[video_name]
```

Return:
```
✓ [video_filename.mov] analyzed successfully
  Visual transcript: <visual_transcript_path>
  Video path: <video_path>
```

**Do NOT update library.yaml** — parent handles this to avoid race conditions in parallel execution.
