---
name: cut
description: Build a cut from a library — scene, selects, roughcut, or custom task. Starts by asking what kind of cut the user wants, then works with them to determine what they want to create. Always exports a file for Final Cut, Premiere, or Resolve at the end. Use when the user asks for a "roughcut", "sequence", "scene", "selects", or any other cut-shaped output.
---

# Skill: Cut

Build a timeline from a library. This skill is the entry point for four kinds of work — the first decision is which one.

## 1. Confirm the library and pre-flight readiness
You need a library before any cut work. If one is already in context from the current conversation, use it. Otherwise show recent libraries (`ruby lib/buttercut/library.rb recent 5`) and let the user pick.

Once the library name is known, check if the library is ready (video processing complete).

```bash
ruby lib/buttercut/library.rb <name> ready
```

Exit code `0` means the library is ready for cut building (`Library.ready?` is the source of truth on what that means — don't re-derive the criteria here). If it exits non-zero, stop. Run `ruby lib/buttercut/library.rb <name> summary` to surface the incomplete clips and tell the user the library needs to finish processing (point them at the `process-library` skill). Don't try to cut around missing clips.

## 2. Determine Task Type
Ask the user with `AskUserQuestion` tool if available. Otherwise ask in text in this order.

Ask plainly. "Roughcut" in the user's opening request is trained vocabulary, not a confirmed choice — present the four options and let them pick. Don't explain to the user why you're asking, and don't apologize for re-asking; the question stands on its own.

You're going to be tempted here to just move forward and assume the user really wants a story shaped roughcut, but they're just using this term loosely. You **absolutely must** tell them the next statement and question before moving forward:

If the library is processed, tell them that it's ready and the number of clips that are processed. Then ask them what kind of cut they want. Again, they probably said "roughcut", but we've just trained them on that word. **You must ask.**

Example framing: "Library is ready. (93/93 clips fully processed.). What kind of cut do you want to build — scene, selects, roughcut, or custom?"

1. **Scene** — one beat or moment, typically 30–60s.
2. **Selects / Find clips** — a flat reel of clips matching some criteria (best takes, mentions of a topic, B-roll on a theme). Length follows the footage.
3. **Roughcut** — a story-shaped cut, 2–8 minutes. Goes through full planning + a sub-agent build.
4. **Custom task** — anything else the user describes.

The roughcut path runs a deeper flow because the agent needs to explore the library broadly, read many summaries, generate fresh contact sheets, and shape a narrative across many clips. The other three paths the main thread handles directly with the user.

## 3. Build the Cut (produces YAML)
Both paths produce a YAML at `libraries/[library-name]/cuts/[slug]_[YYYYMMDD_HHMMSS].yaml`. The export in step 5 is the same regardless of which path you take.

### Roughcut path
Read `skills/cut/roughcut_path.md` and follow it.

### Scene / Selects / Custom path
Read `skills/cut/direct_path.md` and follow it.

## 4. Determine the Editing Application
Now that the cut YAML exists, resolve one editor value for the export:
1. If `library.yaml` has `editor` set, use it.
2. Otherwise fall back to `libraries/settings.yaml`'s `editor` and write the value back to `library.yaml`.
3. If neither has one, ask the user (Final Cut Pro X / Adobe Premiere Pro / DaVinci Resolve), then save the choice to both `library.yaml` and `libraries/settings.yaml`.

## 5. Export the YAML
Run the export with the editor resolved in step 4 and the YAML produced in step 3:

```bash
# Final Cut Pro X
ruby lib/buttercut/export.rb --editor fcpx libraries/[library-name]/cuts/[slug]_[timestamp].yaml libraries/[library-name]/cuts/[slug]_[timestamp].fcpxml

# Premiere Pro
ruby lib/buttercut/export.rb --editor premiere libraries/[library-name]/cuts/[slug]_[timestamp].yaml libraries/[library-name]/cuts/[slug]_[timestamp].xml

# DaVinci Resolve
ruby lib/buttercut/export.rb --editor resolve libraries/[library-name]/cuts/[slug]_[timestamp].yaml libraries/[library-name]/cuts/[slug]_[timestamp].xml
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

## 9. Open in Editor (if enabled)
Check `libraries/settings.yaml` for `open_in_editor_after_export`:
1. If the key is `true`, open the exported file directly in the user's editor.
2. If the key is `false`, skip this step.
3. If the key is missing, ask the user whether exports should be opened automatically, save their answer (`true`/`false`) to `libraries/settings.yaml`, then act on it.

Use `open -a` with the correct application name so macOS doesn't fall back to a text editor or Xcode:

```bash
# Final Cut Pro X
open -a "Final Cut Pro" [xml path]

# Adobe Premiere Pro
open -a "Adobe Premiere Pro" [xml path]

# DaVinci Resolve
open -a "DaVinci Resolve" [xml path]
```

If this is enabled, tell them "I've opened the file for you in __application_name__. Let me know if I can help with anything else."

Use the desktop copy path if step 6 placed one there; otherwise use the library path.


## Guidelines
** Important ** Talk to the user like a video editor, not a programmer. Hide technical details. Don't mention YAML at all. Don't use em or en dashes.

Bad: "Got it — 3-second podium clips only. I'll write the YAML now."
Good: "Got it. Three second podium clips only. I'll start the edit."
Bad: "I have a clear picture of all 48 clips. Let me build the YAML now"
Good: "I have a clear picture of the event. Let me build the edit now."
