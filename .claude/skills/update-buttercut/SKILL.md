---
name: update-buttercut
description: A skill to automatically download and install the latest ButterCut version from GitHub while preserving libraries. Use when user wants to check for updates or update their installation for new features.
---

# Skill: Update ButterCut

Updates ButterCut to the latest version. Uses git pull if available, otherwise downloads from GitHub.

Before updating, always make a backup and encourage the user to save it to a location outside the ButterCut directory. Verify the most recent backup exists and offer to copy it to their Desktop or iCloud Drive.

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
