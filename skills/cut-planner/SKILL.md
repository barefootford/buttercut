---
name: cut-planner
description: Plans a cut (roughcut, sequence, or scene) from a library's clip summaries. Reads all clip summaries, then talks with the user and iteratively creates a plan markdown file until both agent and user are happy and understand the plan.
---

# Skill: Cut Planner

## Overview

In the cut-planner skill, the main thread reads clip summaries from a library to understand footage coverage, then asks the user about the footage to confirm its understanding. It confirms who the characters and locations are, then updates the library.yaml's footage_summary and user_context as it learns more about the footage. If it determines summaries are wrong or missing details, it also updates the summary markdowns.

After confirming its understanding of the footage, it works with the user to create a narrative plan markdown file.

This skill runs in the main thread and does not use a sub-agent.

## Asking the user

Whenever you need the user to pick from a discrete set of options — which library, whether to resume processing, target length, which concept, go/no-go on the plan — use the `AskUserQuestion` tool (or similar option-chip tool the host agent provides) instead of writing a bullet list in chat. Free-form conversation about the footage stays as plain chat; only the moments where you're offering a choice should use the tool.

When the options are libraries (or anything else with a natural "last touched" signal), order them by recency — most recently modified first. For libraries, look at the newest mtime among files inside each library directory (transcripts, summaries, plans, library.yaml itself). The library the user worked on yesterday should be the first chip, not the alphabetical winner.

## Cut Planner Process

### 1. Verify all clips have visual transcripts and summaries
Read `libraries/[library-name]/library.yaml`. Every clip must have `visual_transcript` and `summary` populated. If either is missing for any clip, stop and tell the user which clips still need processing — don't try to plan from incomplete footage. Then ask if they want to resume processing the library.

### 2. Read summaries

#### Sequences
If the user explicitly says they want something short like a short sequence (60 seconds or less), consider asking them about what they want and then grepping through summaries to find the handful of files they might need.

#### Rough Cuts
If the user wants a full roughcut, read every `libraries/[library-name]/summaries/summary_*.md` file. This will give you full knowledge of the library.

### 3. Confirm the footage knowledge and update incorrect summaries
Tell the user what you've learned about the footage, then confirm you understand the Five W's of all the footage: Who, What, When, Where, Why.

Don't tell them "Five W's" or label out Who, What, When, Where, Why, just talk with them conversationally like an assistant editor getting a grip on the footage.

If they want a full roughcut, spend more time. If they just want a sequence, be brief.

Talk with the user until you confirm you understand the footage. Update library.yaml based on the user's responses as you work through questions.

Update footage_summary (locations, characters, narrative, dialogue, clips) and user_context (preferences, goals, etc.) as you iteratively learn more about the footage.

Updating user_context and footage_summary helps future agents understand the footage and the user.

For example, if a summary mentions a generic man or woman but you learn the person is actually the user, replace man/woman with the user's name. Ask the user's name if you don't know it already.

### 4. Ask target length
If available, use the `AskUserQuestion` tool or similar to ask the user what length of video they want to create. Use your judgement based on the footage — options like short sequence (30–60s), medium cut (5–8 min), or longer roughcut (9+ min) make good starting points. Podcast footage will likely require a longer option.

### 5. If creating a roughcut, propose 2–3 concepts (titles only)
Give the user 2–3 genuinely distinct narrative concepts. Keep this round short — it's about picking a direction, not approving a full plan. For each concept, write only:
- **Title** — short, evocative
- **Concept** — 1–2 sentences explaining the angle, tone, or arc

Do **not** include beats, footage suggestions, runtime breakdowns, or format notes yet. Those come in step 6 once a direction is chosen.

Make the options genuinely distinct — different angles, tones, or arcs. End with: "Which feels right, or want me to explore something different?"

If the user just wants a short sequence, give them information about what the sequence will contain.

### 6. Flesh out the chosen concept
Once the user picks a direction for a full roughcut, expand it into a full plan and present that for approval. Now include:
- **Format** — vlog, YouTube Short, long-form, documentary, etc.
- **Beats** — 3–6 beats, each with editorial intent and a rough share of the runtime ("open with ~3 min of X", "montage of Y", "close on Z")
- **Footage suggestions per beat** — name a few videos likely to feed each beat, ie DJI_123, panasonic_1234, etc. Include rough or specific dialogue if you think it will be helpful.
- **Approx. duration**

Iterate on the fleshed-out plan until the user explicitly signals go.

If the user wants a short sequence, be brief, just a few sentences, including dialogue if that makes sense.

### 7. Save the plan
Copy `templates/plan_template.md` to `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md` and fill in every section. The template is the canonical structure — Concept, Format, Target Duration, Beats (with intent / approx. share / footage suggestions), Required Dialogue, Notes for the Build.

The plan is direction. The build agent confirms specific clips inside each beat.

Tell the user the plan is ready and confirm they want to move forward, then invoke the `roughcut` skill, passing the full plan path (`libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md`) as a skill argument — `roughcut` hard-stops if it isn't given one.
