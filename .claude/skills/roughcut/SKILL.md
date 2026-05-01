---
name: roughcut
description: Builds a roughcut YAML and exported XML (Final Cut, Premiere, or Resolve) from an approved plan markdown file produced by `cut-planner`. Spins up a sub-agent that reads only the selected transcripts, assembles the cut, and exports. If the user asks for a "roughcut", "sequence", or "scene" and no plan exists yet, run `cut-planner` first.
---

# Skill: Roughcut Build

Turns an approved plan into a working roughcut YAML and exported XML.

## 1. Locate the Plan
Find the plan markdown at `libraries/[library-name]/roughcuts/plan_*.md`. If multiple exist, ask the user which to use. If none exists, run `video-planner` first.

## 2. Gather Inline Context (Parent Only)
Read once in the parent:
- The plan markdown
- `library.yaml` for the `editor` field and the full video path, audio transcript path, and visual transcript path of each selected video

Sub-agents do not read `library.yaml` or summaries.

## 3. Launch Build Agent

```
Agent tool with:
- subagent_type: "general-purpose"
- description: "Build roughcut YAML and XML from approved plan"
- prompt: [see template below]
```

### Agent Prompt Template

```
You are a video editor AI agent for the "{library_name}" library. The plan is approved — execute it.

APPROVED PLAN:
{paste full plan markdown}

SELECTED VIDEOS:
{for each: filename, full video path, audio transcript path, visual transcript path}

LIBRARY SETTINGS:
- editor: {editor}
- roughcuts directory: libraries/{library_name}/roughcuts/
- transcripts directory: libraries/{library_name}/transcripts/

TASK:
1. Read `.claude/skills/roughcut/agent_instructions.md`
2. Follow steps 5–9 (the plan is already approved)
3. Return paths to the created YAML and XML files
```

## 4. Report Results
Show the user the XML path and confirm it's ready to import into their editor.
