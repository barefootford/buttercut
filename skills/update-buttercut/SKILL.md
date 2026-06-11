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
**If the pull (or the daily gate's `git fetch origin main`) fails:** on a Pro install (`edition` printed `pro`), follow the failure guidance in @pro-update.md instead of this paragraph. Open-source updates come from the public GitHub repo and need no credentials, so a failure means network trouble or GitHub being unreachable. Tell the user and suggest trying again later — don't retry in a loop.

**4. Reinstall dependencies:**
```bash
bundle install
```

**5. Tell the user what they got — in their language:**
```bash
git diff <sha-from-step-1>..HEAD -- CHANGELOG.md
```
The added changelog lines are already written for users — recap them in a sentence or two, the way release notes read, leading with what they can do now ("ButterCut now handles photos — drop stills into a library and use them in cuts"). Then:

- If the changelog didn't change, say they're up to date with the latest behind-the-scenes improvements — don't enumerate what those were.
- Never mention branches, commits, shas, tests, version files, migrations, or `main` in the recap.
- Don't quote version numbers unless the pull brought in a new numbered release section in the changelog. Numbered releases only happen when a batch of changes is publicized as one; between releases the version file lags behind `main` by design, so "still on 0.7.2" is meaningless to the user.
- **Don't run the test suite after updating.** A wall of test output reads as something being wrong, and "the tests pass" answers a question no video editor asked.
- If anything was stashed in step 2, mention it once in plain terms ("I set aside a few local file edits before updating; they're saved if you ever want them back") — don't try to reapply it automatically.

(In developer mode — `.buttercut_developer` present — skip the persona rules above and report technically: versions, shas, and running the suite are all fine.)
