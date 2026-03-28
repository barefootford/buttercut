---
name: detect-scenes
description: Detects scene transitions in videos using AI-powered contact sheet analysis. Generates one XML per scene. Works standalone (any video files) or with a ButterCut library. Use when users say "detect scenes", "find cuts", "scene detection", or "split scenes".
---

# Skill: Detect Scenes

Splits videos into individual scenes using a visual tree search — generate thumbnail contact sheets, identify transitions, refine to precise cut points, export XML.

## Modes

- **Standalone** (default): User gives video paths directly. Output goes to a `buttercut/` subfolder next to the source videos.
- **Library mode**: User references a ButterCut library. Read videos from `library.yaml`, store scene YAMLs in `libraries/[lib]/transcripts/scenes_<basename>.yaml`.

## Key Principles

- **A transition = the primary subject or activity changes.** The person, group, object, or action the camera is focused on shifts to something new.
- **Brief camera movement between subjects is NOT a scene.** Pans, whip-pans, or brief out-of-focus moments connecting two subjects are transition artifacts, not standalone scenes.
- **Err toward more scenes.** When unsure if two segments are the same or different scenes, split them. It's easier for the editor to merge two clips than to re-split one.
- **Check portrait vs landscape per video.** Before exporting, run `ffprobe` on each source video to check its rotation/dimensions. Never assume all videos in a batch share the same orientation.

## Workflow

### Phase 1 — Coarse Scan (parallel, fast)

1. Gather inputs: video paths (or library reference), editor (default: premiere), handles (default: 0)
   - **Library mode**: read `library.yaml` to get video paths
2. Probe each video with `ffprobe` (direct Bash calls, not Task agents) and record per-file:
   - **Duration**
   - **Frame rate** (r_frame_rate, e.g., 25/1, 30/1, 50/1)
   - **Orientation** — check width, height, and rotation side_data to determine portrait vs landscape
   - If frame rates differ across the batch, **warn the user** and ask which sequence frame rate to use (or default to the most common rate). Pass `--sequence-fps` to `export_scenes.rb`.
   - If orientations are mixed, **warn the user** — exports will need per-file rotation handling.
3. Generate contact sheets in parallel (background Bash, 4 at a time):
   ```bash
   ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --output /tmp/cs/cs_<basename>.jpg
   ```
   - Short clips (<45s): quick confirm "one scene? yes/no" — likely single scene
   - Long clips: adaptive interval (5-20s based on duration)
4. View all contact sheets, classify each video:
   - **Single scene** → write YAML immediately, no refinement
   - **Multi-scene** → note approximate transition windows (e.g., "~25-35s")

### Phase 2 — Targeted Refinement (per transition edge only)

Only zoom into the narrow windows identified in Phase 1. Do NOT rescan full videos.

5. For each transition window, generate a zoomed contact sheet (~8s window, 1s intervals):
   ```bash
   ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <T-4> --end <T+4> --interval 1 --output /tmp/cs/cs_<basename>_z<N>.jpg
   ```
6. View and narrow each transition to ~2s precision. The cut must land where the NEW subject is clearly primary — not in the middle of a pan or dead zone.
7. Skip if Phase 1 was already confident (clear subject change)

### Phase 3 — Precise Cut (optional, per transition)

8. If 2s precision isn't enough, zoom once more (0.25s intervals, ~2s window):
   ```bash
   ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <T-1> --end <T+1> --interval 0.25 --output /tmp/cs/cs_<basename>_p<N>.jpg
   ```
9. Pinpoint exact cut frame, write visual description of each scene

### Phase 3b — Verify Clip Boundaries

10. For each detected clip, generate a 2-frame contact sheet showing the FIRST and LAST second:
    ```bash
    ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <in> --end <in+2> --interval 1 --output /tmp/cs/verify_start_<N>.jpg
    ruby .claude/skills/detect-scenes/contact_sheet.rb <video> --start <out-2> --end <out> --interval 1 --output /tmp/cs/verify_end_<N>.jpg
    ```
11. Confirm the same subject appears at both start and end of each clip. If different subjects appear, there's a missed transition — go back and split.

### Phase 4 — Export

**Standalone mode**: output goes into a `buttercut/` subfolder inside the source video directory.
**Library mode**: scene YAMLs go to `libraries/[lib]/transcripts/scenes_<basename>.yaml`, XMLs to `libraries/[lib]/transcripts/xml/`.

10. Write scenes YAML:
    ```yaml
    description: "Detected scenes for <filename>"
    source_video: "<full_path>"
    clips:
      - source_file: "<filename>"
        in_point: "00:00:00.00"
        out_point: "00:00:45.25"
        dialogue: ""
        visual_description: "[Description of scene subject/activity]"
    metadata:
      created_date: "<datetime>"
      total_scenes: N
      video_duration: "HH:MM:SS.ss"
      scene_type: multi_scene | single_scene
    ```
11. Present results table to user showing each scene with timestamps
12. Export one XML per scene:
    ```bash
    ruby .claude/skills/detect-scenes/export_scenes.rb <scenes.yaml> premiere --windows-file-paths [--sequence-fps N]
    ```
    Pass `--sequence-fps` if the batch has mixed frame rates (determined in Phase 1 step 2).
13. Clean up `/tmp/cs_*` contact sheet files

## Output Structure (Standalone)

```
/mnt/d/Videos/Project/
  C1591.MP4                              # original video (untouched)
  C1592.MP4
  buttercut/                             # all generated output
    scenes_C1591.yaml                    # detection results
    scenes_C1592.yaml
    xml/                                 # XML sequences
      C1591_scene_01_<datetime>.xml
      C1591_scene_02_<datetime>.xml
```

## Output Structure (Library Mode)

```
libraries/my-project/
  library.yaml
  transcripts/
    scenes_C1591.yaml
    scenes_C1592.yaml
    xml/
      C1591_scene_01_<datetime>.xml
```

---

## Domain: Social Dance

When detecting scenes in social dance footage (bachata, salsa, kizomba, zouk, etc.), apply these additional rules:

- **A transition = camera pans to different people.** The primary couple in frame changes.
- **Foreground limbs are noise.** Other dancers' arms/bodies passing in front of the camera is NOT a scene change.
- **Together vs breakaway = one scene.** Couples alternate between closed position and open/solo styling — same couple, different moves. Look for the same two people throughout.
- **Roaming shots** where the camera wanders through a crowded floor without focusing on individual couples are a single scene with `scene_type: roaming`.
- **Color over shape.** Two couples may have similar body types or patterns, but different clothing COLORS. Always compare colors explicitly — don't rely on silhouette/pattern alone.
- **Find the new couple, not the gap.** Between couples there's often a brief camera pan where no one is clearly featured. The cut point must be at the END of the pan — the first frame where the NEW couple is clearly the primary subject — NOT at the start of the pan when the old couple leaves.
