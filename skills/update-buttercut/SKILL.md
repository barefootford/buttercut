---
name: update-buttercut
description: A skill to automatically download and install the latest ButterCut version while preserving libraries. Use when user wants to check for updates or update their installation for new features.
---

# Skill: Update ButterCut

Updates ButterCut to the latest version via `git pull`, then recaps what's new in plain video-editor language. Users of this project are video editors — Claude sometimes edits code on its own and may even leave the repo on a side branch. This skill resets that state cleanly: stash anything dirty, switch to `main`, pull, restore deps.

**ButterCut Pro:** first check which edition this is — `ruby lib/buttercut/library.rb edition` prints `core` or `pro` (never gated). If it prints `pro`, this install updates over an authenticated connection — read @pro-update.md in this skill's directory before starting; it adds a license step before the pull and replaces the pull-failure guidance in step 3. `core` means open-source ButterCut: nothing extra to do.

## Workflow

**1. Note the starting point** — remember this sha; after the pull you'll diff the changelog against it to see what arrived:
```bash
git rev-parse HEAD
```

**2. Stash any local changes (tracked + untracked), tagged so the user can find them later:**
```bash
git stash push --include-untracked -m "update-buttercut auto-stash $(date +%Y-%m-%d-%H%M%S)"
```
Always run this — it's a no-op if the working tree is clean. `libraries/` is gitignored and is not touched by stash, pull, or checkout.

**3. Switch to main and pull:**
```bash
git checkout main
GIT_TERMINAL_PROMPT=0 git pull origin main
```
Once the pull succeeds, restart the daily update-check clock so ButterCut doesn't ask about updates again right after this one:
```bash
ruby lib/buttercut/library.rb update_checked
```
**If the pull (or the daily gate's `git fetch origin main`) fails:** on a Pro install (`edition` printed `pro`), follow the failure guidance in @pro-update.md instead of this paragraph. Open-source updates come from the public GitHub repo and need no credentials, so a failure means network trouble or GitHub being unreachable. Tell the user and suggest trying again later — don't retry in a loop.

On Windows, a pull can turn the skills link back into a plain text file (a checkout without Developer Mode can't write symlinks), after which Claude stops seeing ButterCut's skills. After the pull, check it:
```bash
test -d .claude/skills && echo "link OK" || echo "link BROKEN"
```
If it's broken, repair it with Step 7 of `skills/setup/windows-setup.md` before going on.

**4. Reinstall dependencies:**
```bash
bundle install
```

Also sync the WhisperX install to the repo's pinned versions — updates sometimes move them, and `git pull` alone never touches the venv:
```bash
~/.buttercut/venv/bin/pip install --only-binary :all: --no-binary antlr4-python3-runtime,docopt -r requirements.txt
```
On Windows (Git Bash) the venv keeps its tools under `Scripts/` instead of `bin/` — use `~/.buttercut/venv/Scripts/pip.exe` with the same arguments. This is fast and a no-op when the pins haven't changed. If `~/.buttercut/venv` doesn't exist, the install predates the standard venv layout — skip this command (that machine's transcription setup lives wherever `.buttercut_env` points). If it fails because the network dropped, continue the update but tell the user transcription may misbehave until it's re-run.

While you're there (macOS only — Windows installs have no wrapper), if `~/.buttercut/whisperx` exists and contains the line `deactivate`, rewrite it — that older wrapper reported exit 0 even when whisperx crashed:

```bash
grep -q '^deactivate' ~/.buttercut/whisperx 2>/dev/null && printf '%s\n' '#!/bin/bash' 'exec "$HOME/.buttercut/venv/bin/whisperx" "$@"' > ~/.buttercut/whisperx
```

**5. (macOS only) Check that agent shells still resolve the right Ruby — and repair if not.** On Windows, Ruby comes from RubyInstaller on PATH and there's nothing to repair here — skip to step 6.
```bash
"$SHELL" -lc 'ruby --version'
"$SHELL" -c 'ruby --version'
```
Both must print Ruby 3.3.x. Installs set up before mid-2026 are missing a
`~/.zprofile` activation line, so in login shells (`zsh -lc` — how some agentic
clients run commands) macOS's `path_helper` demotes the mise shims and `ruby`
falls back to system Ruby 2.6, which can't parse ButterCut's scripts. If either
command prints 2.6.x (or "command not found"), re-run the mise activation block
from Step 2 of `skills/setup/simple-setup.md` — it's grep-guarded and
idempotent, so it only appends whichever activation lines are missing — then
re-run both checks to confirm 3.3.x. If both printed 3.3.x on the first try,
say nothing about this step. If you repaired it, mention it once in plain terms
("I also patched up a small install issue from an older ButterCut version") —
no shell or PATH talk.

**6. Tell the user what they got — in their language:**
```bash
git diff <sha-from-step-1>..HEAD -- CHANGELOG.md
```
The added changelog lines are already written for users — recap them in a sentence or two, the way release notes read, leading with what they can do now ("ButterCut now handles photos — drop stills into a library and use them in cuts"). Then:

- **Mind the edition split.** A release section may group changes under `### ButterCut (free)` and `### ButterCut Pro`. How you recap the Pro lines depends on the edition you found at the top of this skill (`ruby lib/buttercut/library.rb edition`):
  - On a **Pro** install (`pro`), the user has both — recap free and Pro changes together as things they can now do.
  - On a **core** install (`core`), the user only received the free changes. Recap those as "you can now…", then add the Pro ones as a light, optional heads-up — not as something they have — e.g. "Also new in ButterCut Pro: multi-track timelines and a live preview panel, more at buttercut.io." Keep it to one sentence, never pushy, and skip it entirely if the diff brought no `### ButterCut Pro` lines.
- If the changelog didn't change, say they're up to date with the latest behind-the-scenes improvements — don't enumerate what those were.
- Never mention branches, commits, shas, tests, version files, migrations, or `main` in the recap.
- Don't quote version numbers unless the pull brought in a new numbered release section in the changelog. Numbered releases only happen when a batch of changes is publicized as one; between releases the version file lags behind `main` by design, so "still on 0.7.2" is meaningless to the user.
- **Don't run the test suite after updating.** A wall of test output reads as something being wrong, and "the tests pass" answers a question no video editor asked.
- If anything was stashed in step 2, mention it once in plain terms ("I set aside a few local file edits before updating; they're saved if you ever want them back") — don't try to reapply it automatically.

(In developer mode — `.buttercut_mode` present — skip the persona rules above and report technically: versions, shas, and running the suite are all fine.)
