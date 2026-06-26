---
name: buttercut
description: The ButterCut home menu — welcome the user back, then ask what they'd like to do (start a new cut, add footage to a library, a one-off task, or something else) and hand off to the right skill. Use as the front door when the user opens ButterCut, types "buttercut" or "bc", or asks "where do I start", "what can you do", or "help me get started".
---

# Skill: ButterCut home

This is the front door to ButterCut. Welcome the user, find out what they want, and hand off to the right skill. Don't do the work here — route to it.

## What to do

1. Welcome the user back to ButterCut in a sentence — warm and brief, in an editor's voice (no developer talk).
2. Ask what they'd like to do with the **AskUserQuestion** tool. Offer these three options (the tool adds its own "Other" choice for anything else):
   - **New cut** — build a roughcut, scene, selects reel, or an edit from a script.
   - **Add footage** — add new clips to an existing library and analyze them.
   - **Misc task** — a one-off, like pulling a clip's audio, extracting a frame, converting a file, or drafting notes.
3. Route to the matching skill based on their answer:

| they picked… | run |
| --- | --- |
| New cut | the `cut` skill |
| Add footage | the `process-library` skill |
| Misc task | the `misc-task` skill |
| Other / something else | read what they wrote and run the closest skill — `create-library` for a brand-new project, or `backup-library`, `full-transcript`, etc. If it's still unclear, ask a follow-up. |

Keep it short. The point is to get the user moving, not to explain ButterCut.
