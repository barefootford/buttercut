---
name: setup
description: Sets up a Mac for ButterCut. Installs all required dependencies (Homebrew, Ruby, Python, FFmpeg, WhisperX). Use when user says "install buttercut", "set up my mac", "get started", "first time setup", "install dependencies" or "check my installation".
---

# Skill: Mac Setup

Sets up a Mac for ButterCut. Two installation paths available based on user preference.

## Step 1: Check Current State

Run each check below. Each command exits 0 when the dependency is present. Note which ones fail — that's what setup needs to install.

- [ ] **Xcode CLI Tools** — `xcode-select -p` (fix: `xcode-select --install`)
- [ ] **Homebrew** — `which brew` (fix: see https://brew.sh)
- [ ] **Ruby 3.3.x** — `ruby --version | grep -q 'ruby 3\.3'` (fix: install Ruby 3.3.6, see `.ruby-version`)
- [ ] **Bundler** — `which bundle` (fix: `gem install bundler`)
- [ ] **Python 3.12.x** — `python3 --version | grep -q 'Python 3\.12'` (fix: install Python 3.12.8, see `.python-version`)
- [ ] **FFmpeg** — `which ffmpeg` (fix: see FFmpeg install in the setup file below — must be the `homebrew-ffmpeg/ffmpeg` tap build)
- [ ] **FFmpeg drawtext filter** — `ffmpeg -hide_banner -filters 2>/dev/null | grep -q ' drawtext '` (fix: the stock `brew install ffmpeg` formula often omits drawtext; replace it with the `homebrew-ffmpeg/ffmpeg` tap build — see setup file)
- [ ] **WhisperX** — `which whisperx || test -x ~/.buttercut/whisperx || test -x ~/.buttercut/venv/bin/whisperx` (fix: see setup steps below)
- [ ] **Gems installed** — `bundle check` (fix: `bundle install` in buttercut directory)

If everything passes, tell the user they're ready to go and stop.

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

- **Simple**: Read and follow `skills/setup/simple-setup.md`
- **Advanced**: Read and follow `skills/setup/advanced-setup.md`

## Step 4: Verify Installation

After setup completes, re-run the checklist from Step 1 and report results to the user.
