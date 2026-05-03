---
name: cut-planner
description: Plans a cut (roughcut, sequence, or scene) from a library's clip summaries. Reads all clip summaries, then talks with the user and iteratively creates a plan markdown file until both agent and user are happy and understand the plan.
---

# Skill: Cut Planner

## Overview

In the cut-planner skill, the main thread reads all clip summaries from a library to understand footage coverage, then asks the user about the footage to confirm its understanding. It confirms who the characters and locations are, then updates the library.yaml's footage_summary and user_context as it learns more about the footage. If it determines summaries are wrong or missing details, it also updates the summary markdowns.

After confirming its understanding of the footage, it works with the user to create a narrative plan markdown file.

This skill runs in the main thread and does not use a sub-agent.

## Cut Planner Process

### 1. Verify all clips have visual transcripts and summaries
Read `libraries/[library-name]/library.yaml`. Every clip must have `visual_transcript` and `summary` populated. If either is missing, stop the cut-planner skill — the library hasn't finished processing. Finish processing the library using the appropriate skill, then resume the cut-planner skill once the library is fully processed.

### 2. Read all summaries
Read every `libraries/[library-name]/summaries/summary_*.md` file.

### 3. Confirm the footage knowledge and update incorrect summaries
Tell the user what you've learned about the footage, then confirm you understand the Five W's of all the footage: Who, What, When, Where, Why.

Talk with the user until you confirm you understand the footage. Update library.yaml based on the user's responses as you work through questions.

Update footage_summary (locations, characters, narrative, dialogue, clips) and user_context (preferences, goals, etc.) as you iteratively learn more about the footage.

Updating user_context and footage_summary helps future agents understand the footage and the user.

For example, if a summary mentions a generic man or woman but you learn the person is actually the user, replace man/woman with the user's name. Ask the user's name if you don't know it already.

### 4. Ask target length
If available, use the `AskUserQuestion` tool or similar to ask the user what length of video they want to create. Use your judgement based on the footage — options like short sequence (30–60s), medium cut (5–8 min), or full roughcut (3–15+ min) make good starting points. Podcast footage will likely require a longer option.

### 5. Propose 2–3 concepts (titles only)
Give the user 2–3 genuinely distinct narrative concepts. Keep this round short — it's about picking a direction, not approving a full plan. For each concept, write only:
- **Title** — short, evocative
- **Concept** — 1–2 sentences explaining the angle, tone, or arc

Do **not** include beats, footage suggestions, runtime breakdowns, or format notes yet. Those come in step 6 once a direction is chosen.

Make the options genuinely distinct — different angles, tones, or arcs. End with: "Which feels right, or want me to explore something different?"

### 6. Flesh out the chosen concept
Once the user picks a direction, expand it into a full plan and present that for approval. Now include:
- **Format** — vlog, YouTube Short, long-form, documentary, etc.
- **Beats** — 3–6 beats, each with editorial intent and a rough share of the runtime ("open with ~3 min of X", "montage of Y", "close on Z")
- **Footage suggestions per beat** — name a few videos likely to feed each beat, ie DJI_123, panasonic_1234, etc. Include rough or specific dialogue if you think it will be helpful.
- **Approx. duration**

Iterate on the fleshed-out plan until the user explicitly signals go.

### 7. Save the plan
Write `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md` containing:
- Concept
- Format
- Beats with editorial intent and footage/clip suggestions
- Target duration
- Specific clips to include and why to include them
- Dialogue the user definitely wants to include, either exactly through quotes "Here's how I learned to juggle" or lossily "Include the dialogue about how Kailey's uncle was a magician and taught her to juggle before he died."

The plan is direction. The build agent confirms specific clips inside each beat.

Tell the user you've created the plan and it's now ready for the roughcut agent to create the actual cut. Confirm they want to move forward, then invoke the `roughcut` skill, passing the full plan path (`libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md`) as a skill argument — `roughcut` hard-stops if it isn't given one.
