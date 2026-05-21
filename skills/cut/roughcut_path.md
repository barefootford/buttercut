# Roughcut Path

The Roughcut branch of `skills/cut/SKILL.md` step 3. Run this when the user picked "Roughcut" in step 2. By the time you're here, the library is already confirmed and ready (SKILL.md step 1). Editor resolution happens after the YAML is built (SKILL.md step 4) — don't ask about it yet.

## 1. Plan with the user
Read `skills/cut/roughcut_planning.md` and run that flow — clip coverage, optional script or paper edit, target length, concept proposals, beat structure, iteration, explicit approval. Save the plan markdown at `libraries/[library-name]/plans/plan_[short-name]_[YYYYMMDD_HHMMSS].md`.

## 2. Launch the build sub-agent
Read `skills/cut/roughcut_launch_prompt.md` for the prompt template. Fill in `{library_name}` and `{paste full plan markdown}`, then pass the result as the Agent tool's `prompt`:

```
Agent tool with:
- subagent_type: "general-purpose"
- description: "Build roughcut YAML from approved plan"
- prompt: [filled-in contents of roughcut_launch_prompt.md]
```

The sub-agent reads `library.yaml` directly — it needs the full inventory plus `footage_summary` and `user_context`. This is a deliberate carve-out from the usual parallel-skill contract: `cut` runs as a single agent (no race risk), and editorial work needs broader library context than inline-passing comfortably supports.

## 3. Continue with SKILL.md
The sub-agent returns the YAML path and editorial notes. Continue at step 5 of `SKILL.md` (Export the YAML) — the main thread runs the export uniformly, regardless of which path produced the YAML.
