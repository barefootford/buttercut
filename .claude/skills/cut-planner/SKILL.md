---
name: cut-planner
description: Plans a cut (roughcut, sequence, or scene) from a library's summaries. Reads every summary, asks target length, proposes 2–3 distinct narrative options, iterates until the user picks one, and writes the approved plan to a markdown file the `roughcut` skill consumes. Use this when the user wants a "roughcut", "sequence", or "scene" — this is the planning step before any transcripts are read.
---

# Skill: Cut Planner

Runs entirely in the main thread. No sub-agent.

## 1. Verify Summaries
Read `libraries/[library-name]/library.yaml`. Every video must have `summary` populated. If any are missing, finish those with `summarize-video` first.

## 2. Read All Summaries
Read every `libraries/[library-name]/summaries/summary_*.md` file.

## 3. Ask Target Length
Use `AskUserQuestion`: short sequence (30–60s), medium cut (1–3 min), or full roughcut (3–15+ min).

## 4. Propose 2–3 Narrative Options
Each option:
- **Concept** — 1 sentence
- **Structure** — 2–6 beats
- **Videos used** — filenames with brief reasoning
- **Approx. duration**

Make the options genuinely distinct — different angles, tones, or arcs. End with: "Which feels right, or want me to propose something different?"

## 5. Iterate Until Approved
Refine the chosen option until the user explicitly signals go.

## 6. Save the Plan
Write `libraries/[library-name]/roughcuts/plan_[short-name]_[YYYYMMDD_HHMMSS].md` containing concept, structure, selected video filenames with intent per video, what's skipped, and target duration.

Tell the user the plan path and suggest running `roughcut` to build it.
