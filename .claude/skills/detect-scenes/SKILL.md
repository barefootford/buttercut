---
name: detect-scenes
description: Detects scene transitions in social dance videos using AI-powered contact sheet analysis. Generates one Premiere XML per couple/scene. No library setup or transcription needed. Use when users say "detect scenes", "find cuts", "scene detection", "split by couples", or "dance scenes".
---

# Skill: Detect Scenes

Splits dance videos into individual couple clips using a visual tree search — generate thumbnail contact sheets, identify transitions, refine to precise cut points, export XML.

## Key Principles for Social Dance Footage

- **A transition = camera pans to different people.** The primary couple in frame changes.
- **Foreground limbs are noise.** Other dancers' arms/bodies passing in front of the camera is NOT a scene change.
- **Together vs breakaway = one scene.** Couples alternate between closed position and open/solo styling — same couple, different moves. Look for the same two people throughout.
- **Roaming shots** where the camera wanders through a crowded floor without focusing on individual couples are a single scene with `scene_type: roaming`.

### Common Pitfalls — Watch For These

- **Color over shape.** Two couples may have similar body types or patterns, but different clothing COLORS. Always compare colors explicitly — don't rely on silhouette/pattern alone.
- **Find the new couple, not the gap.** Between couples there's often a brief camera pan where no one is clearly featured. The cut point must be at the END of the pan — the first frame where the NEW couple is clearly the primary subject — NOT at the start of the pan when the old couple leaves.
- **Err toward more scenes.** When unsure if two segments are the same or different couples, split them. It's much easier for the editor to merge two clips than to re-split one.
- **Verify start and end of every clip.** After finalizing cut points, generate a quick contact sheet of the first and last 2 seconds of each clip to confirm the same couple appears at both ends. If different people appear at the start vs end, there's a missed transition inside that clip.
- **Check portrait vs landscape per video.** Before exporting, run `ffprobe` on each source video to check its rotation/dimensions. Some videos in a batch may be portrait (phone held vertically) while others are landscape. ButterCut handles portrait rotation automatically, but mixing orientations in a single batch causes wrong scaling/rotation if not detected per-file. Always verify orientation individually — never assume all videos in a folder share the same orientation.

## Workflow

### Phase 1 — Coarse Scan (parallel, fast)

1. Gather inputs: video paths, editor (default: premiere), handles (default: 0)
2. Get durations via `ffprobe`. Use direct Bash calls (not Task agents) for speed.
3. Generate contact sheets in parallel (background Bash, 4 at a time):
   ```bash
   ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --output /tmp/cs/cs_<basename>.jpg
   ```
   - Short clips (<45s): quick confirm "one couple? yes/no" — likely single scene
   - Long clips: adaptive interval (5-20s based on duration)
4. View all contact sheets, classify each video:
   - **Single couple** → write YAML immediately, no refinement
   - **Roaming pan** → write YAML with `scene_type: roaming`, no refinement
   - **Multi-couple** → note approximate transition windows (e.g., "~25-35s")

### Phase 2 — Targeted Refinement (per transition edge only)

Only zoom into the narrow windows identified in Phase 1. Do NOT rescan full videos.

5. For each transition window, generate a zoomed contact sheet (~8s window, 1s intervals):
   ```bash
   ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <T-4> --end <T+4> --interval 1 --output /tmp/cs/cs_<basename>_z<N>.jpg
   ```
6. View and narrow each transition to ~2s precision. The cut must land where the NEW couple is clearly the primary subject — not in the middle of a pan or dead zone.
7. Skip if Phase 1 was already confident (clear outfit AND color change)

### Phase 3 — Precise Cut (optional, per transition)

8. If 2s precision isn't enough, zoom once more (0.25s intervals, ~2s window):
   ```bash
   ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <T-1> --end <T+1> --interval 0.25 --output /tmp/cs/cs_<basename>_p<N>.jpg
   ```
9. Pinpoint exact cut frame, write visual description of each couple

### Phase 3b — Verify Clip Boundaries

10. For each detected clip, generate a 2-frame contact sheet showing the FIRST and LAST second:
    ```bash
    ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <in> --end <in+2> --interval 1 --output /tmp/cs/verify_start_<N>.jpg
    ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <out-2> --end <out> --interval 1 --output /tmp/cs/verify_end_<N>.jpg
    ```
11. Confirm the same couple appears at both start and end of each clip. If different people appear, there's a missed transition — go back and split.

### Phase 4 — Export

All output goes into a `buttercut/` subfolder inside the source video directory.

10. Write scenes YAML to `<source_video_dir>/buttercut/scenes_<basename>.yaml`:
    ```yaml
    description: "Detected scenes for <filename>"
    source_video: "<full_path>"
    clips:
      - source_file: "<filename>"
        in_point: "00:00:00.00"
        out_point: "00:00:45.25"
        dialogue: ""
        visual_description: "[Couple 1 - man in white shirt, woman in red dress]"
    metadata:
      created_date: "<datetime>"
      total_scenes: N
      video_duration: "HH:MM:SS.ss"
      scene_type: multi_couple | single_couple | roaming
    ```
11. Present results table to user showing each couple with timestamps
12. Export one XML per couple:
    ```bash
    ruby .claude/skills/detect-scenes/export_scenes.rb <source_dir>/buttercut/scenes_<basename>.yaml premiere --windows-file-paths
    ```
13. Clean up `/tmp/cs_*` contact sheet files

## Output Structure

All generated files live in a `buttercut/` subfolder next to the source videos:

```
/mnt/d/Videos/Port Macquarie Latin Festival 2026/
  C1591.MP4                              # original video (untouched)
  C1592.MP4
  buttercut/                             # all generated output
    scenes_C1591.yaml                    # detection results
    scenes_C1592.yaml
    xml/                                 # Premiere XML sequences
      C1591_couple_01_<datetime>.xml
      C1591_couple_02_<datetime>.xml
```
