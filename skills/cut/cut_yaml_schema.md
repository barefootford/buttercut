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
| `clips`          | list of clip objects, in timeline order | The timeline. See per-clip fields below. |
| `metadata.created_date`   | `YYYY-MM-DD HH:MM:SS` | When the YAML was finalized. |
| `metadata.total_duration` | `HH:MM:SS.ss`         | Sum of all clip durations. |

## Per-clip fields

Each entry in `clips:`

| Field                | Format          | Notes |
| -------------------- | --------------- | ----- |
| `source_file`        | filename only   | Bare filename from the clip's entry in `library.yaml` (video or image) — no path. |
| `in_point`           | `HH:MM:SS.ss`   | Start of the cut. Preserve sub-second precision (2.849s → `00:00:02.85`). |
| `out_point`          | `HH:MM:SS.ss`   | End of the cut. Same precision rule. |
| `dialogue`           | string          | Spoken words for the span; concatenate across transcript segments if the cut crosses them. Empty string when the clip is silent / B-roll / a still image. |
| `visual_description` | string          | Shot description based on what the contact sheet shows for this range (for a still, what the image shows). Wrap in brackets to match template style. |

## Still images on the timeline

A still has no intrinsic duration — how long it holds on screen is **your** call, set entirely by `in_point` and `out_point` (the exporter derives the on-spine duration from `out_point - in_point`, exactly as for video).

- Start the still at `in_point: 00:00:00.00` and set `out_point` to the hold length you want.
- **Guideline: about 1 second per still** (`out_point: 00:00:01.00`), adjusting per shot — longer for a hero shot you want to land, shorter in a fast montage.
- Always set the span explicitly: if a still's in/out is missing or zero-length, the exporter falls back to a 4-second hold (`DEFAULT_IMAGE_DURATION` in `lib/buttercut/editor_base.rb`) — much longer than the ~1s guideline.
- Leave `dialogue` empty (stills are silent). Put the shot description from the image's summary in `visual_description`.

Example image clip:

```yaml
- source_file: sunset_over_bay.jpg
  in_point: 00:00:00.00
  out_point: 00:00:01.00
  dialogue: ""
  visual_description: "[Wide still of the bay at sunset, boats silhouetted against orange sky]"
```

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
