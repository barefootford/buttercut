---
name: roughcut
description: Builds a roughcut YAML and exported XML (Final Cut, Premiere, or Resolve) from an approved plan markdown file produced by `cut-planner`. Spins up a sub-agent that reads the library directly, builds the cut iteratively, reviews against format conventions, then returns paths plus conversational editorial notes. If the user asks for a "roughcut", "sequence", or "scene" and no plan exists yet, run `cut-planner` first.
---

# Skill: Roughcut Build

Turns an approved plan into a working roughcut YAML and exported XML. The sub-agent runs async — it commits to a complete cut and returns with notes you can dialogue about.

## 1. Locate the Plan
A plan path **must** be passed in as a skill argument (the format produced by `cut-planner` step 7: `libraries/[library-name]/plans/plan_[short-name]_[timestamp].md`). If no plan path is passed in, stop immediately and return a message to the parent saying a plan path is required and `cut-planner` should be run first. Do not search for plans, do not pick one, do not proceed without one.

## 2. Resolve the Editor (Parent Only)
The sub-agent receives a final editor value:
1. If `library.yaml` has `editor` set, use it.
2. Otherwise fall back to `libraries/settings.yaml`'s `editor` and write the value back to `library.yaml`.
3. If neither has one, ask the user (Final Cut Pro X / Adobe Premiere Pro / DaVinci Resolve), then save the choice to both `library.yaml` and `libraries/settings.yaml`.

## 3. Launch Build Agent

```
Agent tool with:
- subagent_type: "general-purpose"
- description: "Build roughcut YAML and XML from approved plan"
- prompt: [see template below]
```

### Agent Prompt Template

```
You are a video editor AI agent for the "{library_name}" library. The plan below is approved direction — beats, intent, rough length, format. The specific clips are yours to find inside the library. Work iteratively, then review and refine before returning.

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
This sub-agent reads `library.yaml` directly — it needs the full inventory plus `footage_summary` and `user_context`. This is a deliberate carve-out from the parallel-skill contract: `roughcut` runs as a single agent (no race risk), and editorial work needs broader library context than inline-passing comfortably supports.

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
Run the `backup-library` skill. This snapshots the library (yaml, transcripts, summaries, plans, roughcuts) so progress can be restored if needed.

## 7. Report Results
Surface the agent's return message to the user — the YAML path, the library XML path, the desktop XML path (only if step 5 actually copied one), plus the editorial notes. The notes are the conversational hook for what comes next; small fixes you can do directly in the YAML, larger restructures relaunch this skill with a revised plan.
