# Manual Installation

## Platforms

- **macOS** (Apple Silicon) — the primary platform.
- **Windows 10/11** (beta) — via Claude Desktop or Claude Code with **Git for Windows** installed (their Windows shell is Git Bash). Final Cut Pro doesn't exist on Windows, so libraries there target Premiere or Resolve. Status and details: [windows.md](windows.md).

## Requirements

| Dependency | Version | Purpose |
|------------|---------|---------|
| Ruby | 3.3.x (3.3.6 pinned) | XML generation and scripts |
| Python | 3.12.x (3.12.8 pinned) | WhisperX transcription |
| FFmpeg | latest, built with drawtext | Video/audio processing |
| WhisperX | 3.4.2 | Speech-to-text with word timing |

Version files (`.ruby-version`, `.python-version`) are included for compatibility with most version managers (rbenv, pyenv, asdf, mise, etc.). On Windows, Ruby comes from RubyInstaller (with DevKit) and Python from python.org, both via winget.

## Setup Guide

Call the `/setup` skill, or follow the step-by-step instructions directly:

- macOS: [advanced setup guide](../skills/setup/advanced-setup.md)
- Windows: [windows-setup.md](../skills/setup/windows-setup.md)

## Verify Installation

Ask Claude to "check my installation" — the `setup` skill walks through each dependency check and reports anything missing.
