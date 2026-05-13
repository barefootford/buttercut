# Planning a Cut

This is the planning flow for the `roughcut` skill. Work through it with the user before building the timeline. The output is an approved plan markdown file at `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md` that step 2 of SKILL.md consumes.

The library's `footage_summary`, `user_context`, and individual summaries already capture the broad creative context — that was locked in during footage analysis (see "Start Footage Analysis" in AGENTS.md). If anything is confusing you can ask the user, but generally you can just use the summary files and library.yaml for context.

This planning flow runs in the main thread, no sub-agent.

## Asking the user

Whenever you need the user to pick from a discrete set of options — which library, whether to resume processing, target length, which concept, go/no-go on the plan — use the `AskUserQuestion` tool (or similar option-chip tool the host agent provides) instead of writing a bullet list in chat. Free-form conversation about the footage stays as plain chat; only the moments where you're offering a choice should use the tool.

When the options are libraries (or anything else with a natural "last touched" signal), order them by recency — most recently modified first. For libraries, look at the newest mtime among files inside each library directory (transcripts, summaries, plans, library.yaml itself). The library the user worked on yesterday should be the first chip, not the alphabetical winner.

## Planning Process

### 1. Verify all clips have visual transcripts and summaries
Read `libraries/[library-name]/library.yaml`. Every clip must have `visual_transcript` and `summary` populated. If either is missing for any clip, stop and tell the user which clips still need processing — don't try to plan from incomplete footage. Then ask if they want to resume processing the library.

### 2. Read summaries

#### Sequences
If the user explicitly says they want something short like a short sequence (60 seconds or less), consider asking them about what they want and then grepping through summaries to find the handful of files they might need.

#### Rough Cuts
If the user wants a full roughcut, read every `libraries/[library-name]/summaries/summary_*.md` file. This will give you full knowledge of the library. Consider doing a batch read to improve performance if there are lots of summaries to read.

### 3. Use the existing footage context
`library.yaml` (`footage_summary`, `user_context`) and the per-clip summaries are the source of context.

Only ask the user a question if something is genuinely ambiguous *for this cut* — e.g., "the footage covers two arcs, which one is the focus?" or "are the in-vehicle clips meant to be part of this story or unrelated b-roll?".

### 4. Ask for a script or outline
Before proposing concepts, ask the user: "Do you have a script or outline I can use to guide the cut?" Use `AskUserQuestion` with three options:
- **Yes — I'll paste it in** — the user pastes a script or outline.
- **No — let's figure it out from the footage** — proceed with concept proposals (step 6).
- **Give me the full transcript first — I'll do a paper edit** — run the `full-transcript` skill, hand the user the resulting file, and wait for them to come back with their marked-up version (lines/sections circled, reordered, or annotated). Treat the paper edit the same as a pasted script once they return.

If the user provides a script or paper edit, treat it as the primary narrative guide and skip or compress the concept-proposal step (step 6) — the structure is already decided. Still read the summaries for footage coverage, but build the plan around what the user gave you.

### 5. Ask target length
If available, use the `AskUserQuestion` tool or similar to ask the user what length of video they want to create. Use your judgement based on the footage — options like short sequence (30–60s), medium cut (5–8 min), or longer roughcut (9+ min) make good starting points. Podcast footage will likely require a longer option.

### 6. If creating a roughcut, propose 2–3 concepts (titles only)
Give the user 2 distinct narrative structures. Keep this round short — it's about picking a direction, not approving a full plan. For each concept, write only:
- **Title** — short, evocative
- **Concept** — 1–2 sentences explaining the arc and structure

Do **not** include beats, footage suggestions, runtime breakdowns, or format notes yet. Those come in step 7 once a direction is chosen.

Make the options genuinely distinct — different angles or arcs. End by asking the user if any of these structures are what they had in mind with the footage.

If the user just wants a short sequence, give them information about what the sequence will contain.

### 7. Flesh out the chosen concept
Once the user picks a direction for a full roughcut, expand it into a full plan and present that for approval. Now include:
- **Format** — vlog, YouTube Short, long-form, documentary, etc.
- **Beats** — 3–6 beats, each with editorial intent and a rough share of the runtime ("open with ~3 min of X", "montage of Y", "close on Z")
- **Footage suggestions per beat** — name a few videos likely to feed each beat, ie DJI_123, panasonic_1234, etc. Include rough or specific dialogue if you think it will be helpful.
- **Approx. duration**

Iterate on the fleshed-out plan until the user explicitly signals go.

**Any time the user changes the plan — adds a beat, removes a beat, retitles, restructures, adjusts a beat's duration or footage, anything — restate the ENTIRE beat-by-beat plan back to them with the change folded in.** Don't just acknowledge the edit in prose ("got it, Beat 2 is now ~30s") — show every beat again, top to bottom, so the user can see the whole shape after the change. Then ask for the green light.

**You must get an explicit "yes, let's create the roughcut" (or equivalent affirmative — "go", "build it", "let's do it", "ship it") from the user before moving on.** Tweaks, edits, or refinements to the plan are NOT consent to build. A question like "look right?" answered with another tweak request is a continued iteration, not a green light. Default to staying in the iteration loop. If you're unsure whether the user has approved, ask plainly: "Want me to save this plan and start building the roughcut?" — and wait for an unambiguous yes. Saving the plan file and continuing to the build are part of moving forward, so do neither until that yes lands.

If the user wants a short sequence, be brief, just a few sentences, including dialogue if that makes sense. The same explicit-yes rule applies.

### 8. Save the plan
Only after the explicit yes from step 7: copy `templates/plan_template.md` to `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md` and fill in every section. The template is the canonical structure — Concept, Format, Target Duration, Beats (with intent / approx. share / footage suggestions), Required Dialogue, Notes for the Build.

The plan is direction. The build agent confirms specific clips inside each beat.

Once saved, return to `SKILL.md` and continue with step 2 (Resolve the Editor), passing the saved plan path through to the build agent.
