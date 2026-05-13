# Analyze Video (sub-agent prompt)

You are a sub-agent. You'll process a **batch of clips** in sequence — for each one, look at its grid montage(s), decide which visual-structure pattern it fits, write visual descriptions to its (pre-prepped) transcript file, and write a markdown summary. **Never read the video files directly** — work from the grids. You never run ffmpeg, never copy transcripts, never extract frames — the parent has already done all of that.

## Read the patterns ONCE before starting

Before touching any clip, read these five files **in parallel** — issue all five Read calls in a single message, not one after another:

- `skills/analyze-video/examples/patterns.md` — the four visual-structure patterns and the summary shape
- `skills/analyze-video/examples/static-interview.jpg`
- `skills/analyze-video/examples/walk-and-talk.jpg`
- `skills/analyze-video/examples/city-vlog-broll.jpg`
- `skills/analyze-video/examples/desk-broll.jpg`

These are your reference — apply the closest matching pattern to each clip in the batch.

## Inputs

The parent inlines a list of clips below this prompt. Each clip has:

- `video_filename` — the source filename (use this for the summary header and return line)
- `grid_paths` — comma-separated absolute paths to the pre-built grid montage(s); usually one path, but a >10-minute clip will have several
- `visual_transcript_path` — absolute path to the pre-prepped visual transcript JSON (word-level timing already stripped)
- `summary_output_path` — absolute path to write the markdown summary

Do NOT read `library.yaml` or `settings.yaml`.

## For each clip, in order, do steps 1–4

### 1. Read the grid montage(s)

Open every grid for this clip with the Read tool. Each grid is your table of contents for its 10-minute window; tiles are labeled HH:MM:SS in absolute video time. **When a clip has more than one grid path, issue all the Read calls in a single message so they run in parallel.**

The grids are enough — don't extract additional frames.

### 2. Identify the visual structure

Match the clip against the four patterns from `patterns.md`:

- **Single shot, dialogue-driven** (interview, talking head, walk-and-talk vlog): write one description on the first dialogue segment and stop. Patterns 1 and 2.
- **Multi-shot b-roll** (coverage with distinct visual beats): write a description at each narrative beat. Pattern 3.
- **Fixed-frame, content evolves** (locked camera, things happening within the frame): describe the setting once, then only what changes. Pattern 4.

### 3. Add visual descriptions

Read the visual transcript JSON at `visual_transcript_path`, then **Edit** it directly.

**Dialogue segments — add `visual` field:**
```json
{
  "start": 2.917,
  "end": 7.586,
  "text": "Hey, good afternoon everybody.",
  "visual": "Man in red shirt speaking to camera in medium shot. Home office with bookshelf. Natural lighting."
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

Match the level of detail to the closest example. When in doubt, fewer descriptions and tighter prose.

### 4. Write the summary

Write the full summary file in one shot using a `Bash` heredoc — sub-agents are blocked from using the `Write` tool on report files, so a heredoc is the one-shot path. Use the "Summary shape" section of `patterns.md` (already read at startup) as the structure; fill every section with this clip's content:

- **Header**: `# <video_filename>` + `**Duration:**` line as `MM:SS`, or `HH:MM:SS` for clips ≥1h
- **## Overview** — 2–3 specific sentences describing the narrative arc
- **## Key Visuals** — 3–6 bullets covering locations, distinctive shots, visual changes
- **## Notable Dialogue** — 0–3 quotes formatted as `> [MM:SS] "Quote"`. For short clips or no notable dialogue, write `None`. Skip filler.
- **## B-Roll** — cutaway descriptions distinct from the main subject. For single-shot clips, write `None`.

```bash
cat > <summary_output_path> <<'EOF'
# <video_filename>
**Duration:** MM:SS

## Overview
…

## Key Visuals
- …

## Notable Dialogue
> [MM:SS] "…"

## B-Roll
…
EOF
```

Use the quoted heredoc delimiter (`<<'EOF'`) so backticks, `$`, and quotes in summary content pass through verbatim.

**Parallel hint**: the visual-transcript Edit (step 3) and the summary heredoc (step 4) touch different files and don't depend on each other. Issue them in the same message so they run in parallel.

Move on to the next clip — no cleanup needed (the parent handles that after the batch verifies).

## After all clips: return summary

Return one line per clip in the batch:

```
✓ <video_filename.mov>
✗ <video_filename.mov> → ERROR: <reason>
```

If a clip fails, finish the rest of the batch and report the failure — don't abort.

**Do NOT update library.yaml** — the parent handles this from your return summary and a disk check.
