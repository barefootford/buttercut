# Cut YAML Schema

The YAML format every `cut` path produces. Same shape for scenes, selects, custom tasks, and roughcuts — the path differs in *how* the YAML gets built, not *what* it looks like.

## Where it lives

```
libraries/[library-name]/cuts/[slug]_[YYYYMMDD_HHMMSS].yaml
```

Every cut path lands in `cuts/` — scenes, selects, custom tasks, and roughcuts all share the single output directory.

## Seeding the file

Copy the template and overwrite the example clips:

```bash
cp templates/roughcut_template.yaml "libraries/[library-name]/cuts/[slug]_[timestamp].yaml"
```

Generate the timestamp with `date +%Y%m%d_%H%M%S`.

## Top-level fields

| Field            | Format                | Notes |
| ---------------- | --------------------- | ----- |
| `description`    | one-line string       | What the cut is. For selects, use the selection criteria (e.g. "All mentions of Claude Code across interview footage"). |
| `timeline`       | block (optional)      | Explicit output format — see "Timeline format" below. Omit for the usual case (format follows the first video clip). |
| `clips`          | list of clip objects, in timeline order | The timeline. See per-clip fields below. |
| `metadata.created_date`   | `YYYY-MM-DD HH:MM:SS` | When the YAML was finalized. |
| `metadata.total_duration` | `HH:MM:SS.ss`         | Sum of all clip durations. |

## Per-clip fields

Each entry in `clips:`. A clip is either a **video** (trimmed with in/out points) or an **image** (a still held for a duration) — the type is inferred from `source_file`'s extension, so you never declare it.

| Field                | Format          | Applies to | Notes |
| -------------------- | --------------- | ---------- | ----- |
| `source_file`        | filename only   | both       | Bare filename from the clip's entry in `library.yaml` — no path. |
| `in_point`           | `HH:MM:SS.ss`   | video      | Start of the cut. Preserve sub-second precision (2.849s → `00:00:02.85`). |
| `out_point`          | `HH:MM:SS.ss`   | video      | End of the cut. Same precision rule. |
| `duration`           | `HH:MM:SS.ss` or seconds | image | How long the still is held on the timeline. Images have no in/out — they're timeless. Omit to use the default (5s, or `still_duration` in `libraries/settings.yaml`). |
| `dialogue`           | string          | both       | Spoken words for the span; concatenate across transcript segments if the cut crosses them. Empty string when the clip is silent / B-roll / an image. |
| `visual_description` | string          | both       | Shot description (video: what the contact sheet shows for the range; image: what the still depicts, from its summary). Wrap in brackets to match template style. |

### Image (still) clips

A still is one line — a `source_file` and a `duration`:

```yaml
clips:
  - source_file: "DJI_20250423171212_0210_D.mov"
    in_point: "00:00:02.00"
    out_point: "00:00:06.00"
  - source_file: "title-card.png"      # an image — held, not trimmed
    duration: "00:00:03"
```

Remember ButterCut is single-track: a still has no audio of its own, so when the timeline reaches it you cut to silence (and back to sound on the next clip). Don't plan a still as a cutaway "over" continuing dialogue — that's a second track ButterCut doesn't have.

## Timeline format

By default the output format (frame rate, resolution, audio rate) follows the **first video clip** — no `timeline:` block needed. Add one only when:

- **The cut is image-only** (no video clips to inherit from). The block is required here — without it the export falls back to 24fps / 1920×1080. Set it to the format the user is editing in.
- **You want to override** the inherited format (e.g. force 1080p, or a specific frame rate).

```yaml
timeline:
  frame_rate: 24        # whole number, an NTSC rate (23.976 / 29.97 / 59.94), or a fraction string ("30000/1001")
  width: 1920
  height: 1080
```

Any subset is allowed — given keys win, the rest fall back to the first video clip (then to the 24fps/1920×1080 default). Match the user's editing timeline when you set it: a 1080p/24 cut of 4K/23.976 footage should say so explicitly.

## Timestamp format

- `HH:MM:SS.ss` — hours, minutes, seconds with hundredths.
- Always include the hours field, even when zero (`00:00:02.85`, not `0:02.85`).
- Round to hundredths; don't carry more precision than the audio transcript actually provides.

## Fixing transcripts in the `dialogue` field

Whisper transcripts mis-hear technical terms, brand names, proper nouns, and accented speakers. When you can clearly tell from context what was said, write the corrected version into the clip's `dialogue` field. **Never edit the transcript JSON files themselves** — they're the timing source of truth.

Examples:

- "RubyVeedums" → "Ruby Meetups"
- "Cloud Code" → "Claude Code"
- "Hot Wide Native" → "HotWire Native"
