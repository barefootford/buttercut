---
name: report-bug
description: Report a ButterCut bug to the developers — only ever with the user's permission — so it gets fixed for everyone. Use when a command prints "BUTTERCUT ERROR CAPTURED", when ButterCut itself misbehaves (bad export, failed processing), or when the user asks to report a bug or something broken. For "I wish ButterCut could…" use the request-feature skill instead.
---

# Skill: Report Bug

When ButterCut breaks, this skill closes the loop: capture what happened, help the user keep working, and — with their permission — send a technical report to the ButterCut developers so the bug gets fixed at the source.

Two iron rules, no exceptions:

1. **Never edit ButterCut's own code** (`lib/`, `skills/` shipped skills, `scripts/`) to work around a failure. Those files are overwritten by updates, and local patches hide the bug from the fix. A temporary workaround lives in a `user-` skill (`skills/user-my-workaround/`), like any user skill.
2. **Nothing is sent without the user's say-so.** The report is a local file the user can read before anything leaves their machine.

## When this fires

- A ButterCut command printed `BUTTERCUT ERROR CAPTURED: reports/<file>.json` — a crash dump already exists at that path.
- Something failed with **no** dump — ffmpeg died on a clip, an exported timeline won't import, a workflow hit a dead end. Draft a report yourself:
  ```bash
  ruby lib/buttercut/report.rb bug <action> --summary "<short stable title>"
  ```
  (`<action>` is what was being done: export, transcribe, process, cut. The summary becomes the report's title *and* seeds the de-duplication fingerprint — keep it a title, not a paragraph.)
- **Don't report your own mistakes.** A wrong path, a malformed cut file you wrote, a missing field — fix your input and move on. Report only when ButterCut itself misbehaved.
- **Not a bug?** If the user wants something ButterCut simply doesn't do yet, that's the `request-feature` skill, not this one.

## Workflow

**1. Keep the user moving first.** Their video matters more than the bug. If there's a workaround — re-encode an odd clip with ffmpeg, adjust the cut, route around the broken step — try it. Remember what you tried and whether it worked; that goes in the report. Workaround code that's worth keeping goes in a `user-` skill folder, never `lib/`.

**2. Fill in the report file.** It's plain JSON — edit it directly:

- `title` — a one-line summary of the failure. Crash dumps arrive with a generic one (`RuntimeError during export`); replace it with something a developer can triage at a glance.
- `narrative` — markdown: what the user was doing, what failed, what you tried, whether the workaround worked.
- `media` — for each media file involved, run `ruby lib/buttercut/report.rb probe <path>` and append the output to this array. It returns technical metadata only (container, codecs, geometry) with the filename reduced to a basename. A probe *failure* is worth including too — a file ffprobe chokes on may be the whole story.
- `agent` — which agent runtime and model you are, e.g. `{"runtime": "Claude Code", "model": "claude-sonnet-5"}`. Bugs can be model-specific; this field matters.
- `contact_email` — only if the user offers it (see step 3). Default stays `null`.

Leave `kind`, `fingerprint`, and `report_uuid` alone — the server groups and de-duplicates on them.

**Privacy rules (hard):** no transcript text or spoken words, no summaries content, no full paths — basenames only. The narrative sticks to technical facts, never what's *in* the footage.

**3. Ask permission.** Check the standing preference first:

```bash
ruby lib/buttercut/report.rb consent   # → ask | always | never
```

- `never` — don't ask, don't send, stop here. (If the user is the one asking to report, they can flip it: `ruby lib/buttercut/report.rb consent ask`.)
- `always` — say in one sentence that you're sending the bug report they've okayed in the past, and name the file path in case they want to read it first.
- `ask` — give a one-or-two-sentence plain-language summary of what the report says, name the file path so they can read the exact payload, and ask. Offer three choices: send this one, always send (remember it), or never send (remember it). Persist "always"/"never" with `ruby lib/buttercut/report.rb consent always|never`. This is also the moment to offer — optional, off by default — including their email so the developers can tell them when it's fixed.

**4. Send.**

```bash
ruby lib/buttercut/report.rb send reports/<file>.json --user-approved
```

It answers with a JSON outcome:

- `sent` — thank the user in one sentence and move on.
- `already_reported` — this exact failure was reported from this install before; tell the user it's already on the developers' radar and send nothing.
- `failed` — the endpoint is unreachable or unhappy. Say so once, don't retry in a loop; the report file stays in `reports/` and can be sent another day.
- `needs_approval` — you skipped step 3; go back and ask.

**5. Return to the actual task.** Reporting is a side errand — a sentence or two of ceremony, then back to their video.

## Persona

Talk like you're helping an editor, not filing a ticket: "something went wrong in ButterCut while exporting — I've written up a technical report; want me to send it to the developers so they can fix it?" Never paste stack traces or JSON into chat, never call it "telemetry" or "diagnostics data," and never let the reporting errand take over the conversation.

(In developer mode — `.buttercut_mode` present — crash dumps are off by default so raises during development stay quiet; set `BUTTERCUT_FORCE_ERROR_CAPTURE=1` to test the capture path, and report technically, skipping the persona rules.)
