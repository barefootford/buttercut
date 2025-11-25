# Advanced Setup (Developers)

For developers who manage their own Ruby/Python environments. This guide tells you what's needed; you decide how to install it.

## Required Versions

Check `.ruby-version` and `.python-version` in the project root:

- **Ruby**: 3.3.6
- **Python**: 3.12.8

These files are compatible with rbenv, pyenv, asdf, mise, and most version managers.

## Checklist

Work through each item. Skip any you already have.

### 1. Xcode Command Line Tools

```bash
xcode-select -p 2>/dev/null || xcode-select --install
```

### 2. Homebrew

Required for FFmpeg. If you prefer another package manager, adapt accordingly.

```bash
which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Ruby 3.3.6

Install using your preferred version manager (rbenv, asdf, mise, rvm, etc.).

The project includes `.ruby-version` which most managers auto-detect.

Verify:

```bash
ruby --version  # Should show 3.3.6
```

### 4. Bundler

```bash
gem install bundler
```

### 5. Python 3.12.8

Install using your preferred version manager (pyenv, asdf, mise, etc.).

The project includes `.python-version` which most managers auto-detect.

Verify:

```bash
python3 --version  # Should show 3.12.8
```

### 6. FFmpeg

```bash
brew install ffmpeg
```

Or install via your preferred method.

### 7. WhisperX

Two options depending on how you manage Python:

**Option A: Virtual Environment (Recommended)**

Isolates WhisperX dependencies. Creates a wrapper script for easy access.

```bash
mkdir -p ~/.buttercut
python3 -m venv ~/.buttercut/venv
source ~/.buttercut/venv/bin/activate
pip install --upgrade pip
pip install whisperx
deactivate

# Create wrapper script
cat > ~/.buttercut/whisperx << 'EOF'
#!/bin/bash
source ~/.buttercut/venv/bin/activate
whisperx "$@"
deactivate
EOF
chmod +x ~/.buttercut/whisperx

# Add to PATH (adjust for your shell)
echo 'export PATH="$HOME/.buttercut:$PATH"' >> ~/.zshrc
```

**Option B: Direct pip install**

If you manage Python environments yourself and want whisperx globally available:

```bash
pip install whisperx
```

Ensure `whisperx` is in your PATH.

### 8. ButterCut Ruby Dependencies

From the buttercut directory:

```bash
bundle install
```

## Verification

Run the verification script:

```bash
ruby .claude/skills/setup/verify_install.rb
```

All items should show OK.

## Notes

- The `.mise.toml` file is provided for mise users but is not required
- WhisperX uses CPU-only mode for simplicity (no CUDA/GPU setup needed)
- If you use pyenv-virtualenv or similar, you can install whisperx in a dedicated virtualenv instead of `~/.buttercut/venv`
