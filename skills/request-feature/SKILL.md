---
name: request-feature
description: Send a feature request or idea to the ButterCut team. Use when the user says "request a feature", "I wish ButterCut could…", "can you ask the team for…", "suggest an idea", or wishes out loud for something ButterCut doesn't do.
---

# Skill: Request a Feature

The user wants ButterCut to do something it doesn't do. This sends their idea to the people who build it. It always goes through them — you write it up, they approve it, you send it — so it is **not** governed by the error-reporting setting: someone who turned error reports off can still ask for multicam support.

## Step 1 — Make sure it isn't already there

Check skills, `AGENTS.md`, `libraries/settings.yaml`, and `CHANGELOG.md` first — if ButterCut can already do it, just show them how. If it's a Pro feature and they're on the free edition (`ruby lib/buttercut/library.rb edition` prints `core`), tell them it exists in ButterCut Pro instead of sending a request.

## Step 2 — Write it up with them

Draft in their words: a one-line **title** ("Support multicam angles in exports") and a few-sentence **request** — what they're trying to do and why the current way doesn't get them there. The *why* is the useful part. Same rule as bug reports: **their footage stays out of it** — no library, clip, client, or subject names ("a recent two-camera shoot", not "the Hendricks wedding").

## Step 3 — Confirm, then send

Read it back, and only when they approve:

```bash
ruby lib/buttercut/report.rb send \
  --kind feature \
  --title "Support multicam angles in exports" \
  --narrative "Shoots weddings with two cameras and syncs them by hand in Resolve after exporting. Wants both angles to land on the timeline already lined up."
```

If they've saved an email (`ruby lib/buttercut/report.rb consent` shows it), it rides along automatically so the team can reply. If they haven't and they'd want an answer, offer to add `error_report_email:` to `libraries/settings.yaml`.

Then confirm it landed, without promising it'll get built:

> "Sent — that's with the ButterCut team now. No promises on timing, but they read every one."

Don't show them the JSON, the UUID, or a status code. If the send failed, say so plainly and offer to try again later.

---

**Developer mode.** With `.buttercut_mode` present, `report.rb send` refuses. Use `--dry-run` to see what would go.
