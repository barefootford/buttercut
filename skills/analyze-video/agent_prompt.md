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

## 2. Extract frames (scene-detect driven)

Use `extract_frames.rb` — it runs ffmpeg scene-change detection on the clip, then samples frames at the detected change moments (plus first/last, deduped to ≥2s apart, with a 3-frame floor for static clips). This is much more reliable than fixed start/middle/end sampling, which silently misses subjects that enter or change mid-clip.

```bash
ruby .claude/skills/analyze-video/extract_frames.rb <video_path> tmp/frames/[video_name]
```

The script prints JSON with `sampled_timestamps` and `frames[].path`. Read every frame in the `frames` array — these are your full sampling coverage for the clip. The timestamps anchor your segment boundaries: if the script returned 4 frames at 0.5s / 3.2s / 6.1s / 9.1s, those are the natural cut points for splitting the clip into visual segments.

## 3. Add visual descriptions

Read the visual transcript JSON you created in step 1.

**Read the JPG frames** that `extract_frames.rb` produced (paths from its JSON output) using the Read tool, then **Edit** the file at `<visual_transcript_path>`. Do this incrementally — no script needed; just edit the JSON each time you read new frames.

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

**Fully silent B-roll clip (audio transcript has `b_roll: true` and empty `segments`):** the clip itself is B-roll end-to-end. With no dialogue to chunk on, the sampled frames are your only signal. Use the `sampled_timestamps` from `extract_frames.rb` as segment boundaries: each consecutive pair of timestamps becomes a segment whose `visual` describes that interval. Only collapse to a single `0`→`duration` segment if every frame is visually near-identical (truly static clip — extractor will typically return only 3 padding frames in that case). Each segment uses `text: ""`, `b_roll: true`, `words: []`, and a `visual` field.

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
