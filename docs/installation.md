# Manual Installation

## Platforms

- **macOS** (Apple Silicon) — the primary platform.
- **Windows 10/11** (beta) — via Claude Desktop or Claude Code with **Git for Windows** installed (their Windows shell is Git Bash). Final Cut Pro doesn't exist on Windows, so libraries there target Premiere or Resolve.

## Requirements

| Dependency | Version | Purpose |
|------------|---------|---------|
| Ruby | 3.3.6 | XML generation and scripts |
| Python | 3.12.8 | WhisperX transcription |
| FFmpeg | 8.1.x, pinned and checksum-verified by `scripts/install_ffmpeg.sh` (8.1.1 on macOS, 8.1.2 on Windows), built with drawtext | Video/audio processing |
| WhisperX | 3.8.6 (pinned, with pyannote-audio 4.0.7) | Speech-to-text with word timing |

Version files (`.ruby-version`, `.python-version`) are included for compatibility with most version managers (rbenv, pyenv, asdf, mise, etc.). On Windows, Ruby comes from RubyInstaller (with DevKit) and Python from python.org, both via winget.

## Setup Guide

Call the `/setup` skill, or follow the step-by-step instructions directly:

- macOS: [simple-setup.md](../skills/setup/simple-setup.md), or the [advanced setup guide](../skills/setup/advanced-setup.md) if you manage Ruby and Python yourself
- Windows: [windows-setup.md](../skills/setup/windows-setup.md)

## Verify Installation

Ask Claude to "check my installation" — the `setup` skill walks through each dependency check and reports anything missing.
