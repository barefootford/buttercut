---
name: request-feature
description: Send the ButterCut developers a feature request — only ever with the user's permission. Use when the user wishes ButterCut did something it doesn't, says "it would be nice if…", "can ButterCut do X?" and the answer is no, or asks to suggest a feature. For something that's broken, use the report-bug skill instead.
---

# Skill: Request Feature

Editors find the gaps in ButterCut faster than the developers do. This skill turns "I wish it could do X" into a short, specific request the developers actually receive.

**Nothing is sent without the user's say-so.** The request is a local file the user can read before anything leaves their machine.

## When this fires

- The user asks for something ButterCut doesn't do, and you had to tell them no.
- The user explicitly asks to suggest a feature or send feedback.
- You hit a real limitation while working — a format that isn't supported, a step that has to be done by hand — and the user agrees it's worth passing along.

**Don't file a request when:**

- **It's broken, not missing.** ButterCut is supposed to do it and didn't → `report-bug` skill.
- **It already exists.** Check `AGENTS.md`, the skill list, and `CHANGELOG.md` first. Telling the user how to do the thing they wanted beats filing a request for it.
- **It's a Pro feature and they're on core.** Say so — `ruby lib/buttercut/library.rb edition` tells you which edition this install is — and point at buttercut.io rather than filing a request.
- **The user hasn't asked for it.** Don't file requests on your own initiative. This is their voice, not yours.

## Workflow

**1. Sharpen the idea into one line.** Ask the user what they'd want to happen, in their words, before you draft anything. A request that names the concrete outcome ("cut between two camera angles from one take") is worth ten that name a vague wish ("better multicam support"). Keep the title short and stable — it's the de-duplication key, so two editors asking for the same thing in similar words land on one row.

**2. Draft it.**

```bash
ruby lib/buttercut/report.rb feature --title "<one-line request>"
```

That writes `reports/<timestamp>-feature-<fingerprint>.json` and prints the path.

**3. Fill it in.** Plain JSON — edit it directly:

- `narrative` — markdown, and the part that matters most. What the user was trying to do, why the current behavior gets in the way, and what they'd want instead. Concrete beats comprehensive: the actual shoot, the actual timeline, the actual step they had to do by hand.
- `media` — only if the request is about specific footage (a format ButterCut won't take, a camera whose files import wrong). Run `ruby lib/buttercut/report.rb probe <path>` per file and append the output. Skip this for requests that aren't about media.
- `agent` — which agent runtime and model you are, e.g. `{"runtime": "Claude Code", "model": "claude-sonnet-5"}`.
- `contact_email` — only if the user offers it (see step 4). Default stays `null`.

Leave `kind`, `fingerprint`, and `report_uuid` alone. `error` stays `null` — nothing failed here.

**Privacy rules (hard):** no transcript text or spoken words, no summaries content, no full paths — basenames only. Describe the editing problem, never what's *in* the footage. A request about a client's wedding video says "a multi-camera interview," not who was interviewed.

**4. Ask permission.** Same standing preference as bug reports:

```bash
ruby lib/buttercut/report.rb consent   # → ask | always | never
```

- `never` — don't send. Tell the user their preference is set to never and offer to flip it: `ruby lib/buttercut/report.rb consent ask`.
- `always` — say in one sentence that you're sending it, and name the file path in case they want to read it first.
- `ask` — read them the one-line title, name the file path so they can check the exact payload, and ask. This is also the moment to offer — optional, off by default — including their email, so the developers can reach them if it ships or if they have questions.

**5. Send.**

```bash
ruby lib/buttercut/report.rb send reports/<file>.json --user-approved
```

- `sent` — tell the user it's in, in one sentence. Don't promise it'll be built.
- `already_reported` — they've already asked for this from this install; say it's on the list and send nothing.
- `failed` — the endpoint is unreachable. Say so once, don't retry in a loop; the file stays in `reports/` and can be sent another day.
- `needs_approval` — you skipped step 4; go back and ask.

**6. Back to the actual task.** A sentence of ceremony, then return to their video.

## Persona

Talk like you're helping an editor, not filing a ticket: "ButterCut can't do that yet — want me to send it to the developers as a feature request?" Never call it a "ticket," an "issue," or "product feedback." Never paste JSON into chat. And be honest about what sending means: it reaches the developers, it doesn't put it on a roadmap.
