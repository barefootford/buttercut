---
name: contact-sheet
description: Builds a contact sheet from a video clip — evenly spaced frames laid out in a single grid image, each with its hh:mm:ss timestamp burned in. Use when the user asks for a "contact sheet", "grid", "film strip", or wants a one-image overview of part of a clip.
---

# Skill: Contact Sheet

Builds a contact sheet from a slice of a video clip: 16 evenly spaced frames laid out in a 4x4 grid, each annotated with its hh:mm:ss timestamp.

## Prerequisite: ffmpeg with drawtext

This skill burns timestamps onto frames with ffmpeg's `drawtext` filter. The stock Homebrew `ffmpeg` formula frequently ships without it — runs fail with `No such filter: 'drawtext'`. If you hit that error, or want to check up front:

```bash
ffmpeg -hide_banner -filters 2>/dev/null | grep ' drawtext '
```

If nothing prints, replace ffmpeg with the full build from the `homebrew-ffmpeg/ffmpeg` tap so it becomes the only ffmpeg on the machine through brew:

```bash
brew list ffmpeg >/dev/null 2>&1 && brew uninstall --ignore-dependencies ffmpeg || true
brew tap homebrew-ffmpeg/ffmpeg
brew install homebrew-ffmpeg/ffmpeg/ffmpeg
brew link --overwrite homebrew-ffmpeg/ffmpeg/ffmpeg
```

Re-run the grep above to confirm `drawtext` is present, then retry the contact sheet.

## Run

When the clip belongs to a library, always pass `--library` so the output lands in the standard place:

```bash
# Whole clip
ruby skills/contact-sheet/contact_sheet.rb <video-path> --library libraries/<lib>

# From <start> to the end of the clip
ruby skills/contact-sheet/contact_sheet.rb <video-path> <start> --library libraries/<lib>

# Explicit range
ruby skills/contact-sheet/contact_sheet.rb <video-path> <start> <end> --library libraries/<lib>
```

`<start>` and `<end>` accept seconds (e.g. `12.5`) or `HH:MM:SS` / `MM:SS`.

Options: `--library DIR`, `--output PATH` (exact path; overrides `--library`).

Frame count is chosen automatically: 16 frames in a 4x4 grid for clips longer than 10 seconds, 4 frames in a 2x2 grid for clips of 10 seconds or less (avoids duplicates).

Portrait clips (iPhone, etc.) are auto-rotated using the source's container rotation metadata so timestamps land right-side-up. Variable-frame-rate sources (screen recordings, some action cams) are detected and routed through the slower seek-and-grab path automatically.

## Output location

- With `--library DIR`: saved to `<library>/contact_sheets/<clipname>_<descriptor>.jpg`.
  - `<descriptor>` is `full` when covering the whole clip, otherwise `HH-MM-SS_to_HH-MM-SS` (dashes instead of colons).
  - Examples: `contact_sheets/DJI_20251126164651_0278_D_full.jpg`, `contact_sheets/DJI_20251126164651_0278_D_00-00-30_to_00-01-00.jpg`.
  - The `contact_sheets/` directory is created automatically if missing.
- Without `--library` (and no `--output`): saved next to the source video with the same `_<descriptor>` suffix. Fine for quick one-off testing, but library work should always pass `--library`.

## After running

Share the output path as a clickable link so the user can open it directly.
