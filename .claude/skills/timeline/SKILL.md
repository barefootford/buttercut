---
name: timeline
description: Creates video rough cuts using a text-based timeline format optimized for LLM editing. Generates a human-readable timeline from audio transcripts, then creates clip selections and exports to XML. Use this skill when users want to create a "timeline", "rough cut" or "sequence". They all mean the same thing and mean you should use this skill.
---

# Skill: Create Timeline Edit 

This skill creates rough cuts using a simplified text-based timeline format. It's a collaborative, iterative process - the agent proposes structure, makes selections, and refines the edit based on user feedback until the user is satisfied.

**Key features:** Uses a plain-text timeline format optimized for LLM comprehension, focusing on dialogue. B-roll support coming soon.

## Scripts

This skill includes three Ruby scripts:

| Script | Purpose |
|--------|---------|
| `combine_to_timeline.rb` | Converts audio transcripts → text timeline format |
| `dialogue_extractor.rb` | Previews rough cut YAML as readable dialogue |
| `export_to_fcpxml.rb` | Exports rough cut YAML → video editor XML |

**Usage:**
```bash
# Generate text timeline from transcripts
./.claude/skills/timeline/combine_to_timeline.rb [library-name] [timeline-name]
# Output: tmp/[library-name]/[timeline-name]_timeline.txt

# Preview a rough cut by extracting the dialogue
./.claude/skills/timeline/dialogue_extractor.rb libraries/[library-name]/roughcuts/[file].yaml

# Export to video editor xml
./.claude/skills/timeline/export_to_fcpxml.rb [roughcut.yaml] [output.xml] [editor]
# editor: fcpx (default), premiere, or resolve
```

## Library Selection

First, help the user select which library to work with using the AskUserQuestion tool.

**Step 1: Find the 4 most recently modified libraries:**
```bash
ls -td libraries/*/ 2>/dev/null | head -4 | xargs -I {} basename {}
```

**Step 2: Use AskUserQuestion tool** with these options:
- The 4 most recent libraries as individual options (label: library name, description: from footage_summary in library.yaml if available)
- "Create new library" as the final option

Example:
```
AskUserQuestion tool with:
- question: "Which library would you like to create a roughcut for?"
- header: "Library"
- options: [4 recent libraries + "Create new library"]
```

**Step 3: Handle the response:**
- If user selects an existing library → proceed to Prerequisites Check
- If user selects "Create new library" → guide them through library setup (see CLAUDE.md)

## Prerequisites Check

Before launching the timeline agent, verify transcripts are complete:

1. **Verify audio transcripts:**
   Read `libraries/[library-name]/library.yaml` and check that every video entry has:
   - `transcript` populated (audio transcript filename)

   If transcripts are missing:
   - Inform user that transcription must be completed first
   - Ask if they want to run the `transcribe-audio` skill
   - Do not proceed until transcripts are complete

## Gather Roughcut Requirements

After prerequisites are verified, gather details about what the user wants. **Be smart about this** - don't ask about things they've already told you in their initial request.

**Step 1: Analyze what you already know**
- Parse the user's initial request for: target duration, focus/topic, tone, specific content requests
- Read `library.yaml` to understand available footage (footage_summary, user_context, video count)

**Step 2: Ask up to 3 contextual follow-up questions**
Use AskUserQuestion with questions tailored to what's missing and what's in the footage.

**Example question categories** (pick what's relevant and unknown):
- **Duration**: "How long should this roughcut be?" (options: 1-2 min, 3-5 min, 8-10 min, Full length)
- **Focus**: Based on footage_summary, ask which storylines/topics to emphasize
- **Tone**: Casual/conversational vs polished/professional vs raw/documentary
- **Structure**: Chronological vs thematic vs highlight reel
- **Specific content**: If footage has interviews, ask which people to feature; if multiple locations, which to prioritize

**Example with programmer-story-vlog library:**
If user says "make a roughcut", you might ask:
1. "How long should this video be?" (they didn't specify)
2. "What should be the main focus?" (options based on footage: Origin story narration, Ruby meetup interviews, Mix of both)
3. "Should I include the technical meetup presentations or just the interviews?" (specific to this footage)

If user says "5-minute video about the interviews", you'd skip duration and focus, instead asking:
1. "Which interviewees should I prioritize?" (Bart, Eduardo, or equal time for all)
2. "Include any of the narrator's street scenes as transitions?"
3. "Casual conversation feel or more structured Q&A format?"

**Step 3: Compile the creative brief**
Combine the user's initial request + their answers into a clear brief for the timeline agent.

## Launch Timeline Agent

Once prerequisites are verified, launch the timeline agent:

```
Task tool with:
- subagent_type: "general-purpose"
- description: "Create timeline edit from audio transcripts"
- prompt: [See agent prompt template below]
```

### Agent Prompt Template

```
You are a video editor AI agent creating a dialogue edit for the "{library_name}" library.

USER REQUEST: {what_user_asked_for}

LIBRARY CONTEXT:
{paste relevant content from library.yaml - footage_summary, user_context, etc.}

YOUR TASK:
1. Read the timeline creation instructions from .claude/skills/timeline/agent_instructions.md
2. Follow those instructions to create the edit
3. This is a COLLABORATIVE process - work with the user through multiple iterations until they're satisfied
4. Return the path to the final YAML file

DELIVERABLES:
- Timeline file at: tmp/{library_name}/{timeline_name}_timeline.txt
- Rough cut YAML file at: libraries/{library_name}/roughcuts/{timeline_name}_{datetime}.yaml

Begin by reading the agent instructions file.
```

## After Agent Completes

When the agent returns with the YAML file path:

**Step 1: Extract and summarize the dialogue**
- Run `dialogue_extractor.rb` on the YAML file
- Present a summary to the user:
  - Total duration and clip count
  - Structure breakdown (section names with durations)
  - 1-2 sentences of actual dialogue from each section

**Step 2: Ask what they want to do next**
Use AskUserQuestion with these options:

```
AskUserQuestion tool with:
- question: "What would you like to do next?"
- header: "Next step"
- multiSelect: true
- options:
  - label: "Export to editor"
    description: "Generate XML for Final Cut Pro, Premiere, or DaVinci Resolve"
  - label: "Show full dialogue"
    description: "Display complete transcript of the roughcut"
  - label: "Make changes"
    description: "Adjust structure, swap clips, or refine selections"
```

**Step 3: Handle responses**

- **Export to editor**: Ask which editor (FCPX, Premiere, Resolve), run `export_to_fcpxml.rb`, create backup, share path
- **Show full dialogue**: Display the complete dialogue_extractor output
- **Make changes**: See "Suggesting Changes" below

If user selects multiple options, handle them in order (e.g., show dialogue first, then export).

## Suggesting Changes

When the user wants to make changes, don't just ask an open-ended question. Instead:

**Step 1: Launch an agent to analyze the roughcut and suggest improvements**

```
Task tool with:
- subagent_type: "general-purpose"
- model: "haiku"
- description: "Analyze roughcut and suggest improvements"
- prompt: |
    Analyze this roughcut dialogue and suggest 4 improvements: 2 things to ADD and 2 things to REWORK.

    ROUGHCUT DIALOGUE:
    {paste full dialogue from dialogue_extractor.rb}

    ORIGINAL BRIEF:
    {paste the creative brief/user request}

    Suggest 4 concrete improvements:
    - 2 things to ADD (new content, scenes, or elements not currently in the edit)
    - 2 things to REWORK (modify, trim, reorder, or improve existing scenes)

    For each suggestion:
    - Be specific (name clips, sections, or content)
    - Explain the benefit
    - Keep suggestions actionable

    Format:
    ADD:
    1. [Title]: [Brief explanation]
    2. [Title]: [Brief explanation]

    REWORK:
    1. [Title]: [Brief explanation]
    2. [Title]: [Brief explanation]
```

**Step 2: Present suggestions as options**

Note: AskUserQuestion automatically includes an "Other" option, so don't add one manually.

```
AskUserQuestion tool with:
- question: "What changes would you like to make?"
- header: "Changes"
- multiSelect: false
- options:
  - label: "Add: [Add suggestion 1 title]"
    description: [Add suggestion 1 explanation]
  - label: "Add: [Add suggestion 2 title]"
    description: [Add suggestion 2 explanation]
  - label: "Rework: [Rework suggestion 1 title]"
    description: [Rework suggestion 1 explanation]
  - label: "Rework: [Rework suggestion 2 title]"
    description: [Rework suggestion 2 explanation]
```

**Step 3: Apply the changes**
Resume the timeline agent with the selected change (or user's custom request if "Something else").
