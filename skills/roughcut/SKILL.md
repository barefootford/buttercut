---
name: roughcut
description: Plans and builds a roughcut, sequence, or scene from a library. First walks the user through shaping a plan (concepts, beats, length, footage), then builds the timeline as YAML and exports XML for Final Cut, Premiere, or Resolve. Use when the user asks for a "roughcut", "sequence", or "scene".
---

# Skill: Roughcut

Plans a cut with the user, then builds the timeline and exports it for their editor.

## 1. Plan the Cut
If a plan path was passed in as a skill argument (`libraries/[library-name]/plans/plan_[short-name]_[timestamp].md`) and that file already exists, skip to step 2 — the plan is already approved.

Otherwise, read `skills/roughcut/planning.md` and run that flow with the user. It covers verifying clip coverage, asking for a script or paper edit, picking a length, proposing concepts, fleshing out beats, getting explicit approval, and saving the plan markdown.

Only proceed past step 1 once a plan file exists at `libraries/[library-name]/plans/plan_[short-name]_[timestamp].md`.

## 2. Determine the Editing Application (Parent Only)
The sub-agent receives a final editor application value:
1. If `library.yaml` has `editor` set, use it.
2. Otherwise fall back to `libraries/settings.yaml`'s `editor` and write the value back to `library.yaml`.
3. If neither has one, ask the user (Final Cut Pro X / Adobe Premiere Pro / DaVinci Resolve), then save the choice to both `library.yaml` and `libraries/settings.yaml`.

## 3. Decide: Build Directly or Launch Sub-Agent

Two paths depending on how much editorial work is left:

**Build directly in the main thread when the plan is already concrete.** If the approved plan names specific clips AND specific in/out timestamps (or dialogue spans precise enough to map to timestamps via grep on the audio transcript), the exploration work is done. The main thread already has the clips and trims in context from planning — handing off to a sub-agent just rebuilds what's already known. Write the YAML + export yourself following `agent_prompt.md` (YAML structure, dialogue corrections, export command). The export command, copied here so you don't have to chase it:

```bash
# Final Cut Pro X
mise exec -- ruby -Ilib ./.claude/skills/roughcut/export.rb --editor fcpx libraries/[library-name]/roughcuts/[slug]_[timestamp].yaml libraries/[library-name]/roughcuts/[slug]_[timestamp].fcpxml

# Premiere Pro
mise exec -- ruby -Ilib ./.claude/skills/roughcut/export.rb --editor premiere libraries/[library-name]/roughcuts/[slug]_[timestamp].yaml libraries/[library-name]/roughcuts/[slug]_[timestamp].xml

# DaVinci Resolve
mise exec -- ruby -Ilib ./.claude/skills/roughcut/export.rb --editor resolve libraries/[library-name]/roughcuts/[slug]_[timestamp].yaml libraries/[library-name]/roughcuts/[slug]_[timestamp].xml
```

If `mise` is unavailable, drop the `mise exec --` prefix.

**Launch a sub-agent when the plan is beat-level direction.** If the plan describes beats by intent ("find a moment where X", "B-roll over the meetup arrival", multi-minute roughcut spanning many clips), the build needs broad library exploration — reading summaries, scanning transcripts, picking from dozens of candidates. That work belongs in a sub-agent to protect main-thread context.

Rule of thumb: If you have precise dialogue and only 5 or 6 clips, do a direct build yourself. If generating a roughcut that requires exploration, use a sub-agent.

### Sub-agent invocation

```
Agent tool with:
- subagent_type: "general-purpose"
- description: "Build roughcut YAML and XML from approved plan"
- prompt: [see template below]
```

#### Agent Prompt Template

```
You are a video editor AI agent for the "{library_name}" library. The plan below is approved direction — beats, intent, rough length, format. The specific clips are yours to find inside the library. Create an initial draft that focuses on a coherent story with coherent dialogue, then review your work, focusing on the dialogue, consider what improvements should be made, then make those improvements and refine before returning.

LIBRARY YAML: libraries/{library_name}/library.yaml

APPROVED PLAN:
{paste full plan markdown}

EDITOR: {editor}

TASK:
1. Read `.claude/skills/roughcut/agent_prompt.md`
2. Follow the steps there in order (the plan is already approved — don't re-propose)
3. Return paths to the YAML and XML, plus your editorial notes (alternatives, judgment calls, plan deviations) in conversational prose
```

## 4. Context Contract
When a sub-agent is launched, it reads `library.yaml` directly — it needs the full inventory plus `footage_summary` and `user_context`. This is a deliberate carve-out from the parallel-skill contract: `roughcut` runs as a single agent (no race risk), and editorial work needs broader library context than inline-passing comfortably supports.

## 5. Copy XML to Desktop (if enabled)
Check `libraries/settings.yaml` for `save_to_desktop_after_export`:
1. If the key is `true`, copy the exported XML to `~/Desktop/` so it's easy to grab and import into the editor.
2. If the key is `false`, skip this step.
3. If the key is missing, ask the user whether to drop a copy of every export on the Desktop, save their answer (`true`/`false`) to `libraries/settings.yaml`, then act on it.

```bash
cp [library xml path] ~/Desktop/
```

The library copy stays as the canonical artifact; the desktop copy is a convenience drop.

## 6. Backup the Library
Run the `backup-library` skill. This snapshots the entire library directory so progress can be restored if needed.

## 7. Report Results
Surface the agent's return message to the user — the library XML path or the desktop XML path if they have that enabled. Also include very abbreviated editorial notes from the agent. **Do not include the YAML path** — it's an internal build artifact, not something the user opens. The notes are the conversational hook for what comes next; small fixes you can do directly in the YAML and then re-export without another subagent. For very large changes you can assign the work to a (Claude Sonnet or equivalent) subagent to perform.

Also include the one-line import instruction for the editor used:

- **Final Cut Pro X:** Open the cut in Final Cut Pro with File → Import → XML
- **Adobe Premiere Pro:** Open the cut in Premiere with File → Import, then select the XML file
- **DaVinci Resolve:** Open the cut in Resolve with File → Import → Timeline, then select the XML file
