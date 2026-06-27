# Direct Path (Scene / Selects / Custom / Script)

The Scene / Selects / Custom / Script branch of `skills/cut/SKILL.md` step 3. Run this when the user picked Scene, Selects, Script Edit, or Custom in step 2. By the time you're here, the library is already confirmed and ready (SKILL.md step 1). Editor resolution happens after the YAML is built (SKILL.md step 4) — don't ask about it yet.

These task types share one flow because the build mechanism is the same — main thread, conversational YAML, no sub-agent. Only the content of the conversation differs (beats for a scene, criteria for selects, free-form for custom, the written script for a script edit).

## Build the YAML conversationally
Stay in the main thread. Talk with the user about what they want — beats for a scene, criteria for selects, whatever shape the custom task has. Build the YAML iteratively at `libraries/[library-name]/cuts/[slug]_[YYYYMMDD_HHMMSS].yaml`, showing each revision back to the user as it grows, typically as a table like shape. Keep revising until the user explicitly approves that it's ready to export.

The YAML shape — output path, top-level fields, per-clip fields, timestamp format, dialogue-correction policy — is in `skills/cut/cut_yaml_schema.md`. Read it once, then build the file conversationally with the user.

For selects work specifically, set `description` to the selection criteria (e.g. "All mentions of Claude Code across interview footage") so the cut is recognizable when the user opens the timeline.

### Edit from a script
The user already has a written script and wants the cut to follow it line for line. First get the script: they either paste it into the chat, or point you at a file — read it with the Read tool. If they describe a script but haven't given it to you yet, ask them to paste it or hand over the file path before you go further.

Once you have the script, walk it top to bottom and find the footage that delivers each line or beat. Start with the per-clip summaries in `summaries/`, then grep the transcripts (`rg "<a phrase from the script>" libraries/<name>/transcripts/`) to pin the exact clip and timecode where a line is spoken. Build the cut in script order — one clip per beat, trimmed to the in/out points that cover the scripted line.

Set `description` to something that names the script (e.g. "Cut following the launch-video script"). Where the script calls for a line you can't find in the footage, don't invent or force a near-match — list those gaps for the user and let them decide whether to drop the line, reshoot, or swap in something close. Keep revising with the user until they approve the cut.

## Return to SKILL.md
When the user approves the YAML, continue at step 5 of `SKILL.md` (Export the YAML) with the YAML path.
