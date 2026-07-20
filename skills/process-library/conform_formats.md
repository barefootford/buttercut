# Conform mixed-format clips

How to convert a library's outlier clips so every video shares one resolution and frame rate — keeping the originals and all the analysis. Reached from `process-library` Step 5, or after an export prints its mixed-format notice and the user hits scaling/stutter symptoms in their editor. Only run this when the user has said yes to converting; mixed formats are allowed and many editors handle them fine.

## 1. Pick the target format

```bash
ruby lib/buttercut/library.rb <name> format_report
```

The default target is `dominant_format` (the format most clips already have) and the clips to convert are `outlier_clips`. Confirm the plan with the user in plain terms — "I'll convert the two 1080p clips to 4K at 29.97 to match the rest" — before converting anything. Two judgment calls to surface when they apply:

- **Direction.** If the user's deliverable is a specific format (say 1080p), converting the majority *down* can beat upscaling a minority — downscaling looks better than upscaling. The dominant format is a default, not a rule.
- **Portrait clips.** A vertical phone clip conformed to a landscape target gets pillarboxed (black bars left and right). That's correct behavior, but say it out loud so it's not a surprise.

## 2. Convert each outlier with ffmpeg

Write each converted file into a `conformed/` folder next to the original, **keeping the same basename** — the swap in step 3 requires the name to match so the clip keeps its transcript, contact sheet, and summary:

```bash
mkdir -p "<source_dir>/conformed"
ffmpeg -i "<source_dir>/<clip>.<ext>" \
  -vf "scale=<W>:<H>:force_original_aspect_ratio=decrease,pad=<W>:<H>:(ow-iw)/2:(oh-ih)/2,fps=<frame_rate>" \
  -c:v prores_ks -profile:v 2 -c:a pcm_s16le \
  "<source_dir>/conformed/<clip>.mov"
```

- `<W>:<H>` — the target resolution; `<frame_rate>` — the target's **exact fraction** from the report (`30000/1001`, not `29.97`).
- The `scale` + `pad` pair letterboxes/pillarboxes instead of stretching — aspect ratios are never distorted.
- ProRes 422 is the edit-friendly default all three editors import natively; the files are large. If disk space matters more than grading headroom, swap the codec flags for `-c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac -b:a 256k`.
- This is always a re-encode (the size and frame rate change), so long clips take a while. Convert one at a time and keep the user posted.
- Never delete or overwrite the original — it stays exactly where it was.

## 3. Swap the library entry

```bash
ruby lib/buttercut/library.rb <name> replace_media <clip>.<ext> "<source_dir>/conformed/<clip>.mov"
```

`replace_media` points the entry at the converted copy, re-probes the duration, and keeps the transcript, contact sheet, and summary — the basename (minus extension) is unchanged, so every artifact still matches. Neither file on disk is touched.

## 4. Verify

Re-run `format_report` — `uniform` should now be `true`.

Caveat for existing cuts: a cut YAML references clips by filename. If the original's extension wasn't `.mov` (say `clip.mp4` → `conformed/clip.mov`), any pre-existing cut that referenced `clip.mp4` needs its `source_file` entries updated to `clip.mov` before re-exporting. Conforming right after processing — before any cuts exist — avoids this entirely.
