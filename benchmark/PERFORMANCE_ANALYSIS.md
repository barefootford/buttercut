# Frame Detection Performance Analysis

Comparing **fixed-interval sampling** (current approach) vs **FFmpeg scene detection** (proposed in issue #8).

## Performance Characteristics

### Fixed Interval Sampling (Current)

```bash
ffmpeg -ss 00:00:02 -i video.mov -vframes 1 -vf "scale=1280:-1" output.jpg
```

**Cost per frame:**
- Seeks to timestamp: ~10-50ms (fast with `-ss` before `-i`)
- Decodes single frame: ~5-20ms
- Scales and encodes JPEG: ~10-30ms
- **Total: ~25-100ms per frame**

**For a typical workflow (3 frames):**
- Short video (≤30s): 1 frame × 50ms = ~50ms
- Long video (>30s): 3 frames × 50ms = ~150ms
- With subdivision: 6-10 frames × 50ms = 300-500ms

### Scene Detection (Proposed)

```bash
ffmpeg -i video.mov -vf "select='gt(scene,0.4)',showinfo" -f null -
```

**Cost breakdown:**
- **Must decode entire video** - This is the key difference
- Scene detection filter: ~0.5-2ms per frame
- No I/O for detection-only pass

**Processing time depends on video duration:**
- 30fps × duration(s) = total frames to process
- Per-frame decode: ~1-5ms (depends on codec, resolution)
- Scene detection calculation: ~0.5ms per frame

**For a 1-minute video at 1080p/30fps:**
- 1800 frames × ~3ms = ~5.4 seconds for detection
- Plus frame extraction for detected scenes: ~50ms each

### Performance Comparison Table

| Video Duration | Fixed (3 pts) | Scene Detection | Winner |
|---------------|---------------|-----------------|--------|
| 10 seconds    | ~150ms        | ~500-800ms      | Fixed  |
| 1 minute      | ~150ms        | ~5-7 seconds    | Fixed  |
| 5 minutes     | ~150ms*       | ~25-35 seconds  | Fixed  |
| 10 minutes    | ~150ms*       | ~50-70 seconds  | Fixed  |

*Fixed interval stays constant regardless of video length

## Key Insight: Trade-offs

### Scene Detection is SLOWER but SMARTER

**Why scene detection takes longer:**
1. Must decode every frame in the video
2. Calculates histogram difference between consecutive frames
3. Processing time scales linearly with video duration

**Why it's still valuable:**
1. **Automatic** - No human judgment needed for subdivision
2. **Content-aware** - Finds actual scene changes, not arbitrary points
3. **Consistent** - Same threshold produces reproducible results
4. **Better coverage** - Won't miss important transitions

### When to Use Each Approach

**Fixed Interval (faster):**
- Quick preview/triage of footage
- Very long videos (>10 min) where full decode is expensive
- Content known to be relatively static
- Time-critical workflows

**Scene Detection (slower but better):**
- Final/polished visual transcripts
- Action-heavy or dynamic footage
- Batch processing where quality > speed
- Unknown content requiring thorough analysis

## Hybrid Approach (Recommended)

For ButterCut, consider a **two-pass hybrid**:

1. **Quick pass** (current approach): Extract start/middle/end for immediate context
2. **Full analysis** (scene detection): Run in background for detailed scene breakdown

```ruby
# Phase 1: Quick preview (current method) - ~150ms
quick_frames = extract_fixed_interval(video, timestamps: [2, duration/2, duration-2])

# Phase 2: Full scene detection (background) - scales with duration
scene_changes = detect_scenes(video, threshold: 0.4)
detailed_frames = extract_frames(video, timestamps: scene_changes)
```

## Implementation Notes

### Optimizing Scene Detection

1. **Lower resolution for detection:**
   ```bash
   ffmpeg -i video.mov -vf "scale=640:-1,select='gt(scene,0.4)'" ...
   ```
   Processing 640p is ~4x faster than 1080p

2. **Skip frames (trade accuracy for speed):**
   ```bash
   ffmpeg -i video.mov -vf "framestep=2,select='gt(scene,0.4)'" ...
   ```
   Process every 2nd frame = 2x faster, may miss quick cuts

3. **Use hardware acceleration:**
   ```bash
   ffmpeg -hwaccel cuda -i video.mov -vf "select='gt(scene,0.4)'" ...
   ```
   GPU decode can be 5-10x faster

### Content-Specific Thresholds (from issue #8)

| Content Type    | Threshold | Sensitivity |
|-----------------|-----------|-------------|
| Action/Sports   | 0.2-0.3   | High (catches quick cuts) |
| B-roll          | 0.3-0.4   | Medium |
| Interviews      | 0.4-0.6   | Low (static scenes) |
| Presentations   | 0.5-0.7   | Very low |

## Benchmark Scripts

Run these locally to test with your actual footage:

```bash
# Full benchmark comparing both methods
ruby benchmark/frame_detection_benchmark.rb video.mov

# Analyze scene detection at specific threshold
ruby benchmark/scene_detection_analysis.rb video.mov 0.4
```

## Conclusion

**Scene detection is 10-100x slower** than fixed-interval sampling due to full video decode requirement. However, it provides **automatic, content-aware** frame selection that eliminates manual subdivision decisions.

**Recommendation:** Implement as optional enhancement, defaulting to current fast method with scene detection available for thorough analysis workflows.
