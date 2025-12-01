---
name: roughcut
description: Creates video rough cut yaml file for use with Buttercut gem. Concatenates visual transcripts with file markers, creates a roughcut yaml with clip selections, then exports to XML format. Use this skill when users want a "roughcut", "sequence" or "scene" generated. These are all the same thing, just with different lengths.
---

# Skill: Create Rough Cut

This skill handles the editorial process of creating rough cut timeline scripts from transcribed video footage. It launches a specialized agent that analyzes transcripts, makes editorial decisions, outputs a structured YAML rough cut, and exports it to Final Cut Pro XML format.

**Note:** This skill is used for both full-length rough cuts (multiple minutes) and short sequences (30-60 seconds).

## Prerequisites Check

Before launching the roughcut agent, verify all transcripts are complete:

1. **Check library exists:**
   ```bash
   ls libraries/[library-name]/library.yaml
   ```

2. **Verify visual transcripts:**
   Read `libraries/[library-name]/library.yaml` and check that every video entry has both:
   - `transcript` populated (audio transcript filename)
   - `visual_transcript` populated (visual descriptions filename)

   If any visual transcripts are missing:
   - Inform user that transcript processing must be completed first
   - Ask if they want Claude to finish transcript processing using the `transcribe-audio` and `analyze-video` skills
   - Do not proceed with roughcut creation until all transcripts are complete

## Launch Roughcut Agent

Once prerequisites are verified, launch the roughcut creation agent using the Task tool:

```
Task tool with:
- subagent_type: "general-purpose"
- description: "Create rough cut from visual transcripts"
- prompt: [See agent prompt template below]
```

### Agent Prompt Template

When launching the agent, provide a detailed prompt with all necessary context:

```
You are a video editor AI agent creating a rough cut or sequence for the "{library_name}" library.

USER REQUEST: {what_user_asked_for}

LIBRARY CONTEXT:
{paste relevant content from library.yaml - footage_summary, user_context, etc.}

YOUR TASK:
1. Read the roughcut creation instructions from .claude/skills/roughcut/agent_instructions.md
2. Follow those instructions to create the rough cut
3. Return the paths to the created YAML and XML files when complete

DELIVERABLES:
- Rough cut YAML file at: libraries/{library_name}/roughcuts/{roughcut_name}_{datetime}.yaml
- Exported XML file for user's chosen video editor
- Backup created via backup-library skill

Begin by reading the agent instructions file.
```

## After Agent Completes

When the agent returns:
1. Inform the user of the created roughcut file (the xml file, not the yaml file) and its location
2. Confirm the rough cut is ready to import into their video editor
