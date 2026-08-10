---
name: report-bug
description: Report a ButterCut bug to the people who build it. Use automatically when a ButterCut command fails in a way that looks like ButterCut's own fault, and when the user says "report this", "send a bug report", "tell the ButterCut team", or "this is broken".
---

# Skill: Report a Bug

Something in ButterCut broke. Decide whether it's worth reporting, strip the user's work out of it, and send it to the ButterCut team.

The user's footage is theirs. **A report contains no footage, no transcripts, no contact sheets, and no library or clip names** — just what broke and where. Say it that way when you talk about it. Their email goes only if they've said it can.

## Step 1 — Is this worth reporting?

Report when **ButterCut itself broke on work that should have gone through**: a crash, a stack trace, malformed XML, an export that produced nothing, a step that failed on footage the library says is ready.

Don't report: a command you called wrong, a file or library that isn't there, a missing dependency (that's the `setup` skill), or a message that's working as designed (like the daily update check). Try the obvious fix first — if your second attempt works, there's no bug. **Don't report the same failure twice in a session.**

## Step 2 — What has the user agreed to?

```bash
ruby lib/buttercut/report.rb consent
```

Prints `error_reporting=<always|ask|never|unset> email=<address or blank>`.

- **`never`** — stop. Don't send, don't mention it, don't re-ask.
- **`always`** — send (step 4).
- **`ask`** — build the report, run `send` with `--dry-run`, summarize it for the user in plain language (not the JSON — they're a video editor), and send only if they say yes.
- **`unset`** — ButterCut has never asked. Ask now with `AskUserQuestion`: *"ButterCut just hit an error. Want me to send it to the team so they can fix it?"* with three options — **send automatically**, **ask me each time**, **never send** — noting that reports never include footage, transcripts, or library/clip names. Unless they chose never, also ask whether to include their email so an engineer can follow up. Save both answers by editing `libraries/settings.yaml`: set `error_reporting:` and `error_report_email:` (copy the commented block from `templates/settings_template.yaml` if the keys aren't there yet). They can change either any time.

## Step 3 — Take the user's work out of it

Everything you pass to `report.rb` is sent exactly as written. Before passing: `/Users/anna/…` becomes `~/…`; library, clip, and roughcut names become `<library>`, `<clip>.mov`, `<roughcut>.yaml`; anything quoted from a transcript, summary, or script — and any names of people, companies, or clients — gets dropped entirely. Keep the error class, the shape of the message, which step failed, the ButterCut `file.rb:line` frames, and version numbers: those are the whole value of the report.

## Step 4 — Send it

```bash
ruby lib/buttercut/report.rb send \
  --kind bug \
  --action export \
  --class RuntimeError \
  --message "no such file: ~/…/<library>/footage/<clip>.mov" \
  --frame "lib/buttercut/export_core.rb:88" \
  --narrative "Export of a 40-clip sequence failed partway through; the library reported every clip as ready."
```

- `--action` (required) — the step, one word: `export`, `transcribe`, `contact_sheet`, `process`, `cut`, `backup`, or `other`.
- `--class` (required) — the exception class; without a real one use `CommandFailed`.
- `--frame` — the topmost `lib/buttercut/…` line in the trace, if there is one. Skip it rather than inventing one; it's part of how reports get grouped.
- `--narrative` — two sentences at most: what you were doing, what happened. Mention a workaround here if you found one.

The command prints `sent bug report <uuid>` or a one-line reason it didn't. **Either way, that's the end of it.** Never retry, never send twice, never let a failed report become its own topic.

## Step 5 — Say one sentence and get back to work

> "I've sent the error to the ButterCut team — no footage or transcripts, just the error itself. Let's see if we can get around it in the meantime."

Then go help them with the actual problem. Never show them JSON, a UUID, a status code, or a file path from this skill. If it didn't send, don't mention it unless they asked you to report it — then one sentence ("couldn't reach the team just now").

---

**Developer mode.** With `.buttercut_mode` present, `report.rb send` refuses — dev checkouts don't file reports against production. Use `--dry-run` to see what a real install would send.
