# Planning a Cut

This is the planning flow for the `roughcut` skill. Work through it with the user before building the timeline. The output is an approved plan markdown file at `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md` that step 2 of SKILL.md consumes.

The library's `footage_summary`, `user_context`, and individual summaries already capture the broad creative context - that should be filled in during footage analysis (see "Start Footage Analysis" in AGENTS.md).

This planning flow runs in the main thread, not in a sub-agent.

## Asking the user

Whenever you need the user to pick from a discrete set of options use the `AskUserQuestion` tool (or similar option-chip tool the host agent provides) instead of writing a bullet list in chat.

When the options are libraries (or anything else with a natural "last touched" signal), order them by recency - most recently modified first. For libraries, look at the newest mtime among files inside each library directory.

## What to figure out

Work through this list with the user. Generally you'll work through in this order, but you can use judgement on which items to skip. If the user wants a specific, smaller task, you might not need to ask every single question or do every step. Some of these steps will have obvious options to offer using the `AskUserQuestion` tool, but you can add additional options if you think something is missing. Use your judgement.

Ask questions one at a time so you don't end up asking the user questions that don't matter. For example, if they say they just want the intro footage with silence removed, you don't need to read all summaries or propose 2/3 concepts. They're already specifying what they need. Just use whatever tools you need.

1. **Determine the Footage Library** - skip if already established. Otherwise show 5 most recently modified libraries and an "Another Library" option. If they say another library, just show every library as a bullet point without using the `AskUserQuestion` tool. Read the footage library yaml file once you determine which one they want to work with.
2. **Ask what kind of cut** - Scene or short sequence (30–60 seconds) / Roughcut (1-8 minutes) / Custom task.
3. **Target length** - 30-60 seconds/2-4 minutes/5-8 minutes/Other
4. **Does the user have a script or outline they want you to follow?** - Yes - I've got a script or outline I can give you / No, let's figure out the edit together / No, but save the full transcript now as text and I'll edit it down (use full-transcript skill if they want this option.)
5. **Read summaries** - If you're creating a complete roughcut from scratch, read every single clip summary in the library. These are brief and quick to read and give you an idea of the complete footage of the library. If they asked for something else, just read the footage you need to read.
6. **If creating a roughcut, propose 3 concepts (titles + 1–2 sentence arc each)** - Keep it short; this picks a direction, not a full plan. If possible, try and make each concept have a different structure. The first one should be straight forward, the most likely user goal of the footage. Probably linear story telling. The other two should be more creative takes on the footage.
7. **Flesh out the chosen direction** - For a roughcut, expand into Format, Beats (3–6, each with intent + rough runtime share + footage suggestions), and approx. duration. For other work, give a pitch based on what the user tells you. Keep it more brief than you'd expect, but still recommend a structure, bits of dialogue and what files you think could be used.
8. **Iterate with the user.** Determine the direction they want. Ask questions. Each time they make a tweak, show the updated plan to them.
9. **Get an explicit yes before saving.** Tweaks are not consent. After every plan change → restate the whole plan back to the user before asking for the green light. If unsure, ask: "How does this look?"
10. **Save the plan** - only after the explicit yes. Copy `templates/plan_template.md` to `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md` and fill it in.

## Complete the planning
1. **Return to Step 2 of the Roughcut Skill Instructions.** Determine the Editing Application and Launching the build agent.
