# Manual Installation

## Requirements

| Dependency | Version | Purpose |
|------------|---------|---------|
| Ruby | 3.3.6 | XML generation and scripts |
| Python | 3.12.8 | WhisperX transcription |
| FFmpeg | latest | Video/audio processing |
| WhisperX | latest | Speech-to-text with word timing |

Version files (`.ruby-version`, `.python-version`) are included for compatibility with most version managers (rbenv, pyenv, asdf, mise, etc.).

## Setup Guide

See the [advanced setup guide](../.claude/skills/setup/advanced-setup.md) for step-by-step instructions.

## Verify Installation

```bash
ruby .claude/skills/setup/verify_install.rb
```
