---
name: misc-task
description: Help a user handle a one-off production related task that doesn't match perfectly to an existing skill. Examples, pull a clip's audio, extract a frame, transcribe a stray recording, draft notes, create a spreadsheet, convert a file from one type to another, etc. Use when the request doesn't map to other more obvious skills.
---

# Skill: Misc / one-off tasks

Not every request maps to the four core workflow steps (create / process / cut / backup). Editors ask for one-off things. Users will also sometimes ask for features that ButterCut doesn't support natively via XML export.

## Where things go

### Small deliverables tied to a library
For small text or image files, ie notes, a custom transcript or csv file, a JSON index, an extracted frame: save that into the library's `misc/` folder (`libraries/<name>/misc/`). Newer libraries already have it; older ones may not, so run `mkdir -p libraries/<name>/misc` first — it's idempotent, so it's safe whether or not the folder exists.

For large files (multiple megabytes audio or video files), direct the created file to the user's Desktop, home directory or another location. Ask the user.

- **Small deliverables not tied to a library**: Save into the top-level `misc/<YYYY-MM-DD>/<task-name>/` directory — one dated folder per day, a task-named folder inside it (e.g. `misc/2026-06-22/youtube-title-ideas/ideas.md`). Small files only: markdown, JSON, HTML, text, and the like. `misc/` is gitignored.
- **Large in-work / scratch files** (video, audio, intermediate renders): write to the repo's top-level `tmp/` directory. It's gitignored scratch space — fine for anything mid-task you don't need to keep. Delete when the task is done and the large file has been saved where the user prefers it.
- **Large finished output the user wants to keep** (a converted clip, an extracted audio file — anything over roughly 1 MB): never store it inside ButterCut. Write it to the user's Desktop (`~/Desktop`) or a path they specify, and hand it back by path.

## Unsupported file features
If users ask for you to do something that isn't natively supported by ButterCut for their video editor (Final Cut, Premiere, Resolve) tell the user plainly that ButterCut doesn't support it yet (subtitles, motion graphics, etc), but you can tell them that if you want you can explore and attempt to accomplish the task as Claude/ChatGPT, Software Engineer and video afficionado. You'll need to tell them that this isn't guaranteed to work but you'll try your best. Don't change core /lib files to attempt this. Instead create temporary ruby/xml/etc scripts inside the tmp directory.

For example, taking an existing XML file, then researching how XML adds subtitles, then attempting to modify the XML directly. 

Again, tell the user this is not supported natively by ButterCut, but you can explore attempting to do it. Save these non-native modified XML filles inside the library's misc directory if they're library related and text or image based. `libraries/<name>/misc/` Never modify ButterCut's library files (lib) to achieve these goals. Treat these as read-only as every ButterCut update will restore these to the main production Buttercut.

For larger files, ask the user if they'd like them saved to their desktop, home folder, or movies directory, whatever seems appropriate given the custom task.

After you attempt the work, ask the user if it was successful and iterate until it works or you've exhausted options. If it is successful, you can ask the user if they'd like to save details about how to accomplish it again as a custom user skill, ie `user-plan-script`, `user-create-subtitles`, etc. Details in AGENTS.md.
