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

Required for FFmpeg and libyaml. If you prefer another package manager, adapt accordingly.

**Note:** Homebrew installation requires interactive terminal access (password prompts, confirmations). If running via an agent, the user must run the install command manually.

```bash
which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 3. Libyaml (Ruby Dependency)

Required for Ruby's psych extension. Install before compiling Ruby:

```bash
brew install libyaml
```

### 4. Ruby 3.3.6

Install using your preferred version manager (rbenv, asdf, mise, rvm, etc.).

The project includes `.ruby-version` which most managers auto-detect.

Verify:

```bash
ruby --version  # Should show 3.3.6
```

### 5. Bundler

Skip this step if you installed Ruby via mise — the precompiled Ruby tarball ships with Bundler. Otherwise:

```bash
gem install bundler
```

### 6. Python 3.12.8

Install using your preferred version manager (pyenv, asdf, mise, etc.).

The project includes `.python-version` which most managers auto-detect.

Verify:

```bash
python3 --version  # Should show 3.12.8
```

### 7. FFmpeg (full build with drawtext)

The contact-sheet pipeline uses the `drawtext` filter to burn timestamps onto frames. The stock Homebrew `ffmpeg` formula often omits drawtext (requires libfreetype + libharfbuzz at build time). Install the `homebrew-ffmpeg/ffmpeg` tap build instead:

```bash
# Remove stock ffmpeg if present so the tap version links cleanly
brew list ffmpeg >/dev/null 2>&1 && brew uninstall --ignore-dependencies ffmpeg || true

brew tap homebrew-ffmpeg/ffmpeg
brew install homebrew-ffmpeg/ffmpeg/ffmpeg
brew link --overwrite homebrew-ffmpeg/ffmpeg/ffmpeg
```

If you build ffmpeg yourself, ensure it's configured with `--enable-libfreetype` (and `--enable-libharfbuzz` on recent versions).

Verify:

```bash
ffmpeg -hide_banner -filters 2>/dev/null | grep ' drawtext '
```

Must print a `drawtext` line. If nothing prints, contact-sheet generation will fail.

### 8. WhisperX

Two options depending on how you manage Python:

**Option A: Virtual Environment (Recommended)**

Isolates WhisperX dependencies. Creates a wrapper script for easy access.

```bash
mkdir -p ~/.buttercut
python3 -m venv ~/.buttercut/venv
source ~/.buttercut/venv/bin/activate
pip install --upgrade pip
pip install 'whisperx==3.4.2' 'pyannote-audio==3.4.0'
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
pip install 'whisperx==3.4.2' 'pyannote-audio==3.4.0'
```

Ensure `whisperx` is in your PATH.

### 9. ButterCut Ruby Dependencies

From the buttercut directory:

```bash
bundle install
```

## Verification

Re-run the checklist in `skills/setup/SKILL.md` (Step 1). Every item should pass.

## Notes

- The `.mise.toml` file is provided for mise users but is not required. It pins `ruby.compile = false` and `python.compile = false` so `mise install` pulls precompiled binaries (Ruby from jdx/ruby, Python from python-build-standalone) instead of building from source. Requires mise >= 2025.12.4. Override in your user config if you'd rather compile.
- WhisperX uses CPU-only mode for simplicity (no CUDA/GPU setup needed)
- If you use pyenv-virtualenv or similar, you can install whisperx in a dedicated virtualenv instead of `~/.buttercut/venv`
