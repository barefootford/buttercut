---
name: update-buttercut
description: A skill to automatically download and install the latest ButterCut version from GitHub while preserving libraries. Use when user wants to check for updates or update their installation for new features.
---

# Skill: Update ButterCut

Updates ButterCut to latest version. Uses git pull if available, otherwise downloads from GitHub.
Before doing this always make a backup and encourage the user to save the most recent backup to another location outside the buttercut directory. For example, verify the most recent backup and also offer to duplicate the most recent library to their Desktop or an iCloud directory.

## Workflow

**1. Check current version:**
```bash
cat lib/buttercut/version.rb
```

**2. Check if git repo:**
```bash
git rev-parse --git-dir 2>/dev/null
```

**3a. If git repo exists:**
```bash
# Check for uncommitted changes
git status --porcelain

# If changes exist, STOP and inform user to commit/stash first

# Pull latest
git pull origin main
bundle install
```

**3b. If not git repo:**
```bash
# Download latest
curl -L https://github.com/barefootford/buttercut/archive/refs/heads/main.zip -o /tmp/buttercut-latest.zip
unzip -q /tmp/buttercut-latest.zip -d /tmp/

# Update files (excludes libraries/)
rsync -av --exclude 'libraries/' --exclude '.git/' /tmp/buttercut-main/ ./
bundle install
rm -rf /tmp/buttercut-latest.zip /tmp/buttercut-main
```

**4. Verify:**
```bash
cat lib/buttercut/version.rb
bundle exec rspec
```

If tests fail, STOP and report issue. Show old and new version numbers.
