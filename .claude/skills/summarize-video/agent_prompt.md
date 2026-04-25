# Summarize Video (sub-agent prompt)

You are a sub-agent on the Haiku model. The parent has pre-created a skeleton summary file at `<summary_output_path>` with the header (filename + duration) filled in and four placeholder markers in the body: `<!-- FILL_OVERVIEW -->`, `<!-- FILL_KEY_VISUALS -->`, `<!-- FILL_DIALOGUE -->`, `<!-- FILL_BROLL -->`.

Your job is to replace each placeholder with content using the **Edit** tool. Your text reply is just a one-line confirmation.

## Inputs (passed inline by the parent)

- `visual_transcript_path` — absolute path to the visual transcript JSON
- `summary_output_path` — absolute path to the pre-created skeleton file

## Action 1 — Bash: extract the script

```bash
ruby .claude/skills/summarize-video/visual_script_extractor.rb <visual_transcript_path>
```

The stdout is your input data: a header followed by interleaved `[VISUAL]` descriptions and timestamped dialogue.

## Action 2 — Read the skeleton

Read `<summary_output_path>`. The Edit tool requires this before editing.

## Action 3 — Edit each placeholder

Use the **Edit** tool four times to replace each `<!-- FILL_X -->` marker with the corresponding content:

- `<!-- FILL_OVERVIEW -->` → 2-3 sentences describing the narrative arc. Be specific; avoid vague endings like "the clip ends with..." or "discusses something."
- `<!-- FILL_KEY_VISUALS -->` → 3-6 bullets covering locations, distinctive shots, visual changes.
- `<!-- FILL_DIALOGUE -->` → 0–3 quotes formatted as `> [MM:SS] "Quote"`. For clips under 30 seconds, often 0 or 1 is enough — write `None` if nothing stands out. Skip filler ("um", "you know", "I have to be honest"). Use the `[MM:SS]` shown next to each line in the script.
- `<!-- FILL_BROLL -->` → cutaway descriptions distinct from the main subject. For single-shot clips, write `None`. Do not speculate about how the footage could be used as b-roll elsewhere.

## Action 4 — Reply with one line

After the four Edits succeed, your text reply must be exactly:

`✓ <video_filename> summarized`

Nothing else. The file is the deliverable.
