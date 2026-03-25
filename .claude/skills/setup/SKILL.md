---
name: setup
description: Sets up Ubuntu 24.04 for ButterCut. Installs all required dependencies (Ruby, Python, FFmpeg, WhisperX). Use when user says "install buttercut", "set up", "get started", "first time setup", "install dependencies" or "check my installation".
---

# Skill: Ubuntu Setup

Sets up Ubuntu 24.04 for ButterCut. Two installation paths available based on user preference.

## Step 1: Check Current State

First check if Ruby is available, then run the appropriate check:

```bash
if command -v ruby &>/dev/null; then
  ruby .claude/skills/setup/verify_install.rb
else
  echo "Ruby not found — checking other dependencies..."
  command -v python3 && python3 --version
  command -v ffmpeg && ffmpeg -version 2>&1 | head -1
  command -v whisperx && echo "WhisperX OK" || echo "WhisperX missing"
fi
```

If all dependencies pass (or Ruby reports all OK), inform the user they're ready to go.

## Step 2: Ask User Preference

If dependencies are missing, use AskUserQuestion:

```
Question: "How would you like to install ButterCut?"
Header: "Install type"
Options:
  1. "Simple (recommended)" - "Fully automatic setup. We'll install everything for you using sensible defaults."
  2. "Advanced" - "For developers who want control. You manage Ruby/Python versions with your preferred tools."
```

## Step 3: Run Appropriate Setup

Based on user choice:

- **Simple**: Read and follow `.claude/skills/setup/simple-setup.md`
- **Advanced**: Read and follow `.claude/skills/setup/advanced-setup.md`

## Step 4: Verify Installation

After setup completes, run verification. Use mise activation if needed:

```bash
eval "$($HOME/.local/bin/mise activate bash)" 2>/dev/null; export PATH="$HOME/.buttercut:$PATH"
ruby .claude/skills/setup/verify_install.rb
```

Report results to user. Note: on Linux, Xcode CLI Tools and Homebrew checks do not apply — ignore any MISSING for those.
