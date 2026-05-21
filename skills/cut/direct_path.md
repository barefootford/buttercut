# Direct Path (Scene / Selects / Custom)

The Scene / Selects / Custom branch of `skills/cut/SKILL.md` step 3. Run this when the user picked Scene, Selects, or Custom in step 2. By the time you're here, the library is already confirmed and ready (SKILL.md step 1). Editor resolution happens after the YAML is built (SKILL.md step 4) — don't ask about it yet.

These three task types share one flow because the build mechanism is the same — main thread, conversational YAML, no sub-agent. Only the content of the conversation differs (beats for a scene, criteria for selects, free-form for custom).

## Build the YAML conversationally
Stay in the main thread. Talk with the user about what they want — beats for a scene, criteria for selects, whatever shape the custom task has. Build the YAML iteratively at `libraries/[library-name]/cuts/[slug]_[YYYYMMDD_HHMMSS].yaml`, showing each revision back to the user as it grows. Keep revising until the user explicitly approves that it's ready to export.

The YAML shape — output path, top-level fields, per-clip fields, timestamp format, dialogue-correction policy — is in `skills/cut/cut_yaml_schema.md`. Read it once, then build the file conversationally with the user.

For selects work specifically, set `description` to the selection criteria (e.g. "All mentions of Claude Code across interview footage") so the cut is recognizable when the user opens the timeline.

## Return to SKILL.md
When the user approves the YAML, continue at step 5 of `SKILL.md` (Export the YAML) with the YAML path.
