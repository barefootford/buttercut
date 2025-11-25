---
name: setup
description: Sets up a Mac for ButterCut. Installs all required dependencies (Homebrew, Ruby, Python, FFmpeg, WhisperX). Use when user says "install buttercut", "set up my mac", "get started", "first time setup", "install dependencies" or "check my installation".
---

# Skill: Mac Setup

Sets up a Mac for ButterCut. Two installation paths available based on user preference.

## Step 1: Check Current State

First, run the verification script to see what's already installed:

```bash
ruby .claude/skills/setup/verify_install.rb
```

If all dependencies pass, inform the user they're ready to go.

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

After setup completes, run verification again:

```bash
ruby .claude/skills/setup/verify_install.rb
```

Report results to user.
