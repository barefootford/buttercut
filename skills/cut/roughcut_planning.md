# Planning a Roughcut

This is the planning flow for the **Roughcut** path of the `cut` skill. By the time you're here, the user has already chosen "Roughcut" as the task type and the editor is already resolved — your job is to shape the editorial direction with them and save an approved plan markdown file at `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md`. Step 4 of SKILL.md hands that plan to the build sub-agent.

The library's `footage_summary`, `user_context`, and individual summaries already capture the broad creative context — those are filled in during footage analysis (see "Start Footage Analysis" in AGENTS.md).

This planning flow runs in the main thread, not in a sub-agent.

## Asking the user

Whenever you need the user to pick from a discrete set of options use the `AskUserQuestion` tool (or similar option-chip tool the host agent provides) instead of writing a bullet list in chat.

When the options are libraries (or anything else with a natural "last touched" signal), order them by recency — most recently modified first. For libraries, use `ruby lib/buttercut/library.rb recent [N]` — it scans every file inside each library dir, which is the right signal for "what was the user working on" (footage analysis writes transcripts/sheets/summaries; `library.yaml` alone is stale).

## What to figure out

Work through this list with the user. Generally you'll work through in this order, but use judgement — if the user has already conveyed something earlier in the conversation, skip that question.

Ask questions one at a time so you don't end up asking the user questions that don't matter.

1. **Target length** — 2–4 minutes / 5–8 minutes / Other.
2. **Does the user have a script or outline they want you to follow?** — Yes, I've got a script or outline I can give you / No, let's figure out the edit together / No, but save the full transcript now as text and I'll edit it down (use the `full-transcript` skill if they pick this option).
3. **Read summaries** — read every clip summary in the library. They're brief and cheap to read and give you a complete sense of the footage.
4. **Propose 3 concepts** (titles + 1–2 sentence arc each). Keep it short — this picks a direction, not a full plan. Try to give each concept a different structure. The first should be the straightforward, most-likely user goal, probably linear storytelling. The other two should be more creative takes.
5. **Flesh out the chosen direction** — expand into Format, Beats (3–6, each with intent + rough runtime share + footage suggestions), and approximate duration.
6. **Iterate with the user.** Each time they tweak, show them the updated plan.
7. **Get an explicit yes before saving.** Tweaks are not consent. After every plan change, restate the whole plan back to the user before asking for the green light. If unsure, ask: "How does this look?"
8. **Save the plan** — only after the explicit yes. Copy `templates/plan_template.md` to `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md` and fill it in.

## Complete the planning
Return to step 4 of `SKILL.md` and launch the build sub-agent with the saved plan.
