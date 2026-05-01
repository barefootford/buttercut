---
name: cut-planner
description: Plans a cut (roughcut, sequence, or scene) from a library's clip summaries. First it reads all clip summaries, then it has a dialogue with the user and iteratively creates a plan markdown file until agent and user are happy and understand plan.
---

# Skill: Cut Planner

## Overview

The cut-planner is a skill where the main thread reads all clip summaries from a library to understand footage coverage, then asks the user about the footage to confirm it's understanding about the footage. It should confirm who character's and locations are, and then update update the library.yaml's footage_summary and user_context as it goes and learns more about the footage. If it determines summaries are wrong or missing details, it should also also update summary markdowns.

After it confirms it's understanding of the footage, it works with the user to to create a narrative plan markdown file.

This skill runs in the main thread and does not use a sub-agent.

## Cut Planner Process

1. Verify visual transcripts and summaries are present for all clips

Read `libraries/[library-name]/library.yaml`. Every clip must have `visual_transcript` and `summary` populated. If either are missing, the agent must stop. This means the library hasn't finished processing. The agent should stop the cut-planner skill and instead finish processing the library, using the appropriate skill to finish library processing. When the library is completely processed, the agent can resume using the cut-planner skill.

2. Read All Summaries

Read every `libraries/[library-name]/summaries/summary_*.md` file.

3. Confirm the footage knowledge and update incorrect summaries.

Tell the user what you've learned about the footage, then confirm with the user you understand the Five W's of all of the footage. Who, What, When, Where, Why.

The agent talks with the user until the agent confirms they understand the footage. The agent updates library.yaml based on the user's responses as it works through questions.

Update footage_summary (locations, characters, narrative, dialogue, clips) and user_context (preferences, goals, etc) as you iteratively learn more about the footage.

Updating user_context and footage_summary helps future agents understand the footage and the user.

For example, if the summary mentiones a generic man, woman, etc, but learns that the person is actually the person using ButterCut, they can replace "man" with "Andrew" or woman with "Kailey" after asking the user for their name (unless they already know, then they don't need to ask again). 

3. Ask Target Length
If available to the agent, use the `AskUserQuestion` tool or similiar tool to ask the user about what type of length video they're hoping to create. Use your judgement based on the footage, but options like short sequence (30–60s), medium cut (5-8 min), or full roughcut (3–15+ min) are good starting options. If the footage is a podcast it will likely require a longer option.

## 4. Propose 2–3 Narrative Options
Give the user a few narrative options, using your best judgement from the conversation and footage.
- **Concept** — 1 sentence
- **Beats** — 3–6 beats, each with editorial intent and a rough share of the runtime ("open with ~3 min of X", "montage of Y", "close on Z")
- **Format** — vlog, YouTube Short, long-form, documentary, etc. Influences pacing in the build.
- **Footage suggestions per beat** — name a few videos likely to feed each beat, ie DJI_123, panasonic_1234, etc. Include rough or specific dialogue if you think it will be helpful.
- **Approx. duration**

Make the options genuinely distinct — different angles, tones, or arcs. End with: "Which feels right, or want me to explore something different?"

## 5. Iterate Until Approved
Refine the chosen option until the user explicitly signals go.

## 6. Save the Plan
Write `libraries/[library-name]/plans/[short-name]_[YYYYMMDD_HHMMSS].md` containing:
- Concept
- Format
- Beats with editorial intent and footage/clip suggestions
- Target duration
- Specific clips to include and why to include them
- Dialogue the user definitely wants to include, either exactly through quotes "Here's how I learned to juggle" or lossily "Include the dialogue about how Kailey's uncle was a magician and taught her to juggle before he died."

The plan is direction. The build agent confirms specific clips inside each beat.

Tell the user you've created the plan and it's now ready for the the roughcut agent to create the actual cut. Confirm that they want to move forward and then invoke the roughcut skill and hand off the plan.
