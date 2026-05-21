---
name: update-buttercut
description: A skill to automatically download and install the latest ButterCut version from GitHub while preserving libraries. Use when user wants to check for updates or update their installation for new features.
---

# Skill: Update ButterCut

Updates ButterCut to the latest version via `git pull`. Users of this project are video editors — Claude sometimes edits code on its own and may even leave the repo on a side branch. This skill resets that state cleanly: stash anything dirty, switch to `main`, pull, restore deps.

## Workflow

**1. Check current version:**
```bash
cat lib/buttercut/version.rb
```

**2. Stash any local changes (tracked + untracked), tagged so the user can find them later:**
```bash
git stash push --include-untracked -m "update-buttercut auto-stash $(date +%Y-%m-%d-%H%M%S)"
```
Always run this — it's a no-op if the working tree is clean. `libraries/` is gitignored and is not touched by stash, pull, or checkout.

**3. Switch to main and pull:**
```bash
git checkout main
git pull origin main
```

**4. Reinstall dependencies:**
```bash
bundle install
```

**5. Verify:**
```bash
cat lib/buttercut/version.rb
bundle exec rspec
```

Show old and new version numbers. If anything was stashed in step 2, tell the user it's saved in `git stash` (reference the stash message) so they can recover it if needed — don't try to reapply it automatically.
