---
name: update-buttercut
description: A skill to automatically download and install the latest ButterCut version while preserving libraries. Use when user wants to check for updates or update their installation for new features.
---

# Skill: Update ButterCut

Updates ButterCut to the latest version, then recaps what's new in plain video-editor language. Users of this project are video editors — Claude sometimes edits code on its own and may even leave the repo on a side branch. The updater resets that state cleanly on its own: it fetches, and when there is something to apply it stashes anything dirty, switches to `main`, fast-forwards, and syncs dependencies. Your job is to run it and tell the user what arrived.

**ButterCut Pro:** on a Pro install (`ruby lib/buttercut/library.rb edition` prints `pro`; `core` is open-source ButterCut) the updater signs in to the update server with the license the installer saved. There's nothing extra for you to run — read @pro-update.md in this skill's directory only to interpret its failure messages.

## Workflow

**1. Run the updater — one command, nothing else:**
```bash
ruby lib/buttercut/update.rb
```
Never assemble the steps yourself (`git stash`, `git checkout`, `git pull`, `git config`, `bundle install`, `pip install`): the updater already does them, and on Pro it is the only thing that knows how to sign in. `libraries/` is gitignored and untouched by any of this. The command prints one JSON object:

- `updated` — whether anything new arrived. `before`/`after` are the shas (developer mode only cares).
- `changelog` — the lines the update added to CHANGELOG.md, already written for users. Step 2 recaps them; you don't need to run git to see them.
- `stashed` — the stash name when local edits were set aside, otherwise `null`. Edits are only set aside when there was something to apply; a current install is left exactly as found.
- `dependencies` — `bundle`, `whisperx` (the venv synced to the repo's pinned versions), and `whisperx_wrapper` (an older macOS wrapper that hid crashes, rewritten when found), each `ok`, `repaired`, `failed`, or `skipped`. `skipped` is normal (Windows, or an install that predates the standard venv layout). If `whisperx` is `failed`, the update still went through — tell the user transcription may misbehave until it's re-run, and re-run the updater later.
- `shell_ruby_ok` — macOS only (`null` elsewhere). `false` means agent shells no longer resolve the right Ruby: installs set up before mid-2026 are missing a `~/.zprofile` activation line, so in login shells (`zsh -lc` — how some agentic clients run commands) macOS's `path_helper` demotes the mise shims and `ruby` falls back to system Ruby 2.6, which can't parse ButterCut's scripts. Re-run the mise activation block from Step 2 of `skills/setup/simple-setup.md` — it's grep-guarded and idempotent, so it only appends whichever activation lines are missing — then mention it once in plain terms ("I also patched up a small install issue from an older ButterCut version"), no shell or PATH talk. When it's `true`, say nothing about it.
- `skills_link_ok` — `false` means a Windows checkout turned the `.claude/skills` link back into a plain text file (a checkout without Developer Mode can't write symlinks), after which Claude stops seeing ButterCut's skills. Repair it with Step 7 of `skills/setup/windows-setup.md` before going on.
- `error` + `message` — the update didn't complete. Tell the user what the message says, in plain terms, and don't retry in a loop.
  - `network` — the fetch failed before anything was touched. Open-source updates come from the public GitHub repo and need no credentials, so this means network trouble or GitHub being unreachable — suggest trying again later.
  - `local` — the update was downloaded but the install's own state blocked applying it (a local commit that diverged from `main`, a merge that isn't a fast-forward). Waiting won't help. If `stashed` is set, the user's edits are already saved in that stash and the repo may be on `main` — say so. Show the message, and offer to untangle it (in video-editor mode, ask before touching git).
  - `unexpected` — the updater itself broke (the message names the error). If `stashed` is set, the user's edits are saved in that stash. Tell the user the update didn't finish, then run the `report-bug` skill.
  - `license_missing` / `license_declined` (Pro only): follow @pro-update.md.

The updater also restarts the daily update-check clock, so ButterCut won't ask about updates again right after this one.

**2. Tell the user what they got — in their language.** The `changelog` lines from step 1 are already written for users — recap them in a sentence or two, the way release notes read, leading with what they can do now ("ButterCut now handles photos — drop stills into a library and use them in cuts"). Then:

- **Mind the edition split.** A release section may group changes under `### ButterCut (free)` and `### ButterCut Pro`. How you recap the Pro lines depends on the edition you found at the top of this skill (`ruby lib/buttercut/library.rb edition`):
  - On a **Pro** install (`pro`), the user has both — recap free and Pro changes together as things they can now do.
  - On a **core** install (`core`), the user only received the free changes. Recap those as "you can now…", then add the Pro ones as a light, optional heads-up — not as something they have — e.g. "Also new in ButterCut Pro: multi-track timelines and a live preview panel, more at buttercut.io." Keep it to one sentence, never pushy, and skip it entirely if the update brought no `### ButterCut Pro` lines.
- If `changelog` is empty but `updated` is true, say they're up to date with the latest behind-the-scenes improvements — don't enumerate what those were. If `updated` is false, they were already current.
- Never mention branches, commits, shas, tests, version files, migrations, or `main` in the recap.
- Don't quote version numbers unless the update brought in a new numbered release section in the changelog. Numbered releases only happen when a batch of changes is publicized as one; between releases the version file lags behind `main` by design, so "still on 0.7.2" is meaningless to the user.
- **Don't run the test suite after updating.** A wall of test output reads as something being wrong, and "the tests pass" answers a question no video editor asked.
- If `stashed` was set, mention it once in plain terms ("I set aside a few local file edits before updating; they're saved if you ever want them back") — don't try to reapply it automatically.

(In developer mode — `.buttercut_mode` present — skip the persona rules above and report technically: versions, shas, and running the suite are all fine.)
