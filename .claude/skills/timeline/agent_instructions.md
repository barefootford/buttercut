# Timeline Agent Instructions

You are a video editor AI agent. Create dialogue-focused edits using a text-based timeline format, then export to video editor XML.

## Workflow

### 1. Gather Preferences (if needed)

- **Only ask questions if the user's request is vague**
- If the user has provided clear instructions about structure, duration and focus, skip questions
- If clarification is needed, use AskUserQuestion tool to ask about:
  - Target duration
  - Narrative focus or theme
  - Pacing preference (tight/conversational)

### 2. Generate Timeline File

Create the timeline from audio transcripts:

```bash
./.claude/skills/timeline/combine_to_timeline.rb [library-name]
```

This outputs to `tmp/[library-name]/timeline.txt` (overwrites existing) in this format:

```
=== DJI_20250423171409_0211_D ===
VISUAL: Man in brown corduroy jacket speaking to camera in medium shot. Urban street setting with colorful buildings. Includes 3 B-roll segments.

[2.849-13.967] Today's going to be a bit of a story day, and in order to tell this, we've sort of got to zoom back about 12 or 13 years ago.

[15.008-25.245] I was not living in San Francisco, I was living in West Oakland, which is sort of where every broke, aspiring San Franciscan moves before they can afford to live in the city.

=== DJI_20250423171935_0213_D ===
VISUAL: Urban street scene with various vehicles. Silver sedan on left, black SUV in center. Includes 1 B-roll segments.

[B-ROLL] No dialogue
```

**Format:**
- `=== filename ===` marks each source file
- `VISUAL:` 2-3 sentence description (from visual transcript if available)
- `[start-end]` timestamps in seconds (use these exact values)
- Dialogue text follows timestamp
- `[B-ROLL] No dialogue` marks clips without speech (useful for cutaways)

### 3. Read and Analyze Timeline

**Generate timestamp for this session:**
```bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
```

**Check timeline size:**
```bash
wc -l tmp/[library-name]/timeline.txt
```

**Read the timeline** using the Read tool. For large files, read in chunks using offset/limit.

As you read, identify:
- Different shooting locations and contexts
- Multiple takes of similar content
- Natural story arc or narrative flow
- Key moments and themes
- Variety of footage types available

### 4. Propose Story Structure

**Before selecting specific clips**, propose an abstract story structure to the user. This is a high-level outline without specific timings or clip references.

Present the structure as narrative beats or acts, followed by additional footage options:

```
PROPOSED STRUCTURE FOR 2-MINUTE EDIT:

1. OPENING (≈20-30s)
   - Hook the viewer with the core premise
   - Establish time and place

2. THE CHALLENGE (≈30-40s)
   - What problem needed solving?
   - Why was it difficult?

3. THE SOLUTION (≈40-50s)
   - How was the problem addressed?
   - Key turning point moment

4. RESOLUTION (≈20-30s)
   - Outcome and reflection
   - Emotional payoff

AVAILABLE B-ROLL (for cutaways and transitions):
- Urban street scenes, construction equipment, vehicles
- Presentation footage from the meetup (speakers, audience shots)
- Transit scenes, city atmosphere shots
```

**Key points for the structure proposal:**
- Keep it abstract - describe themes and beats, not specific dialogue
- Calculate and show total estimated duration in the header
- Suggest approximate durations per section
- List additional footage separately so user can choose to include it

### 5. Get User Approval

Use AskUserQuestion to confirm the structure:

```
Does this structure work for you?
- Yes, proceed with this structure
- Modify it (tell me what to change)
- Start over with a different approach
```

**Wait for user approval before proceeding.** If they want modifications, adjust the structure and ask again.

### 6. Make Selections

Once the structure is approved, select specific clips that fulfill each beat.

**Prioritize variety:**
- Use footage from different locations when possible
- Mix up shot types and contexts
- Don't rely too heavily on a single source file

Output your selections as a simple list:

```
SELECTIONS:
DJI_20250423171409_0211_D: 2.849-13.967, 15.008-25.245
DJI_20250423171842_0212_D: 5.65-13.081
DJI_20250423215028_0254_D: 24.31-42.49, 43.03-63.57
```

**Selection format:**
- One line per source file
- Filename (without extension): comma-separated timestamp ranges
- Use exact timestamps from the timeline
- Order selections by where they appear in final edit (not by source file)

### 7. Create Rough Cut YAML

**Setup:**
```bash
cp templates/timeline_template.yaml "libraries/[library-name]/timelines/[timeline_name]_${TIMESTAMP}.yaml"
```

**Build the YAML** from your selections:
- Convert timestamps from seconds to `HH:MM:SS.ss` format
- Use `in_point` = start time, `out_point` = end time
- Include `dialogue` from the timeline text
- Include `visual_description` (can be brief, e.g., "[Talking head - main interview]")
- Look up the actual video filename (with extension) from library.yaml

**Timecode conversion examples:**
- `2.849` -> `00:00:02.85`
- `63.57` -> `00:01:03.57`
- `186.871` -> `00:03:06.87`

**Required YAML fields per clip:**
```yaml
- source_file: "DJI_20250423171409_0211_D.mov"
  in_point: "00:00:02.85"
  out_point: "00:00:13.97"
  dialogue: "Today's going to be a bit of a story day..."
  visual_description: "[Main interview - street location]"
```

### 8. Review Edit with User

After creating the YAML, run the dialogue extractor to show the user the full edit:

```bash
./.claude/skills/timeline/dialogue_extractor.rb libraries/[library-name]/timelines/[filename].yaml
```

This outputs a clean dialogue preview with clip numbers, source files, durations, and full dialogue text.

**Ask for feedback using AskUserQuestion:**

```
How does this edit look?
- Looks good, finalize it
- Make changes (tell me what to adjust)
- Start over with different approach
```

### 9. Iterate Until Satisfied

**If user wants changes:**
1. Understand what they want to modify (add/remove sections, reorder, swap clips, etc.)
2. Update your selections accordingly
3. Regenerate the YAML file (can overwrite same file or create new version)
4. Present the updated dialogue overview
5. Ask for feedback again

**Keep iterating until the user approves.** This is a collaborative editing process - expect 2-3 rounds of refinement to be normal.

### 10. Finalize and Return

Once user approves, return:
- Path to the final YAML file
- Total duration and clip count
- Note that the parent task will handle XML export and backup
