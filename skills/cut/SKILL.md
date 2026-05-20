---
name: cut
description: Build a cut from a library — scene, selects, roughcut, or custom task. Starts by asking what kind of cut the user wants, then works with them to determine what they want to create. Always exports a file for Final Cut, Premiere, or Resolve at the end. Use when the user asks for a "roughcut", "sequence", "scene", "selects", or any other cut-shaped output.
---

# Skill: Cut

Build a timeline from a library. Despite the singular name, this skill is the entry point for four kinds of work — the first decision is which one.

## 1. Confirm the library and pre-flight readiness
You need a library before any cut work. If one is already in context from the current conversation, use it. Otherwise show recent libraries (`ruby skills/buttercut-lib/library.rb recent 5`) and let the user pick.

Once the library name is known, gate on `Library.ready?`:

```bash
ruby skills/buttercut-lib/library.rb <name> ready
```

Exit code `0` means the library is ready for cut building (`Library.ready?` is the source of truth on what that means — don't re-derive the criteria here). If it exits non-zero, stop. Run `ruby skills/buttercut-lib/library.rb <name> summary` to surface the incomplete clips and tell the user the library needs to finish processing (point them at the `process-library` skill). Don't try to cut around missing clips.

## 2. Determine Task Type
Ask the user with `AskUserQuestion` if available. Otherwise ask in text in this order:

1. **Scene** — one beat or moment, typically 30–60s.
2. **Selects / Find clips** — a flat reel of clips matching some criteria (best takes, mentions of a topic, B-roll on a theme). Length follows the footage.
3. **Roughcut** — a story-shaped cut, 2–8 minutes. Goes through full planning + a sub-agent build.
4. **Custom task** — anything else the user describes.

**Always ask, even when the user says "roughcut" in the request.** Users have been saying "create a new roughcut" for months — it's the trained vocabulary, not necessarily the output they want. Confirm task type every time before branching.

The roughcut path runs a deeper flow because the agent needs to explore the library broadly, read many summaries, generate fresh contact sheets, and shape a narrative across many clips. The other three paths the main thread handles directly with the user.

## 3. Determine the Editing Application
Resolve one editor value for the export:
1. If `library.yaml` has `editor` set, use it.
2. Otherwise fall back to `libraries/settings.yaml`'s `editor` and write the value back to `library.yaml`.
3. If neither has one, ask the user (Final Cut Pro X / Adobe Premiere Pro / DaVinci Resolve), then save the choice to both `library.yaml` and `libraries/settings.yaml`.

## 4. Build the Cut (produces YAML)
Both paths produce a YAML at `libraries/[library-name]/roughcuts/[slug]_[YYYYMMDD_HHMMSS].yaml`. The export in step 5 is the same regardless of which path you take.

### Roughcut path
Read `skills/cut/roughcut_path.md` and follow it.

### Scene / Selects / Custom path
Read `skills/cut/direct_path.md` and follow it.

## 5. Export the YAML
Run the export with the editor resolved in step 3 and the YAML produced in step 4:

```bash
# Final Cut Pro X
ruby -Ilib skills/cut/export.rb --editor fcpx libraries/[library-name]/roughcuts/[slug]_[timestamp].yaml libraries/[library-name]/roughcuts/[slug]_[timestamp].fcpxml

# Premiere Pro
ruby -Ilib skills/cut/export.rb --editor premiere libraries/[library-name]/roughcuts/[slug]_[timestamp].yaml libraries/[library-name]/roughcuts/[slug]_[timestamp].xml

# DaVinci Resolve
ruby -Ilib skills/cut/export.rb --editor resolve libraries/[library-name]/roughcuts/[slug]_[timestamp].yaml libraries/[library-name]/roughcuts/[slug]_[timestamp].xml
```

## 6. Copy XML to Desktop (if enabled)
Check `libraries/settings.yaml` for `save_to_desktop_after_export`:
1. If the key is `true`, copy the exported XML to `~/Desktop/` so it's easy to grab and import into the editor.
2. If the key is `false`, skip this step.
3. If the key is missing, ask the user whether to drop a copy of every export on the Desktop, save their answer (`true`/`false`) to `libraries/settings.yaml`, then act on it.

```bash
cp [library xml path] ~/Desktop/
```

The library copy stays as the canonical artifact; the desktop copy is a convenience drop.

## 7. Backup the Library
Run the `backup-library` skill. This snapshots the entire library directory so progress can be restored if needed.

## 8. Report Results
Surface the path to the XML — the library path, or the desktop path if that's enabled. For roughcuts, also include very abbreviated editorial notes from the sub-agent's return message; small fixes you can do directly in the YAML and re-export without another sub-agent. **Do not include the YAML path** — it's an internal build artifact, not something the user opens.

Include the one-line import instruction for the editor used:

- **Final Cut Pro X:** Open the cut in Final Cut Pro with File → Import → XML
- **Adobe Premiere Pro:** Open the cut in Premiere with File → Import, then select the XML file
- **DaVinci Resolve:** Open the cut in Resolve with File → Import → Timeline, then select the XML file
