# Advanced Setup (Developers)

For developers who manage their own Ruby/Python environments on Ubuntu 24.04. This guide tells you what's needed; you decide how to install it.

## Required Versions

Check `.ruby-version` and `.python-version` in the project root:

- **Ruby**: 3.3.6
- **Python**: 3.12.8

These files are compatible with rbenv, pyenv, asdf, mise, and most version managers.

## Checklist

Work through each item. Skip any you already have.

### 1. System Build Dependencies

Required before building Ruby:

```bash
sudo apt-get install -y libyaml-dev libssl-dev libreadline-dev zlib1g-dev libxml2-utils
```

### 2. Ruby 3.3.6

Install using your preferred version manager (rbenv, asdf, mise, rvm, etc.).

The project includes `.ruby-version` which most managers auto-detect.

With mise (precompiled, fastest):

```bash
curl https://mise.run | sh
~/.local/bin/mise settings ruby.compile=false
~/.local/bin/mise trust && ~/.local/bin/mise install
```

Verify:

```bash
ruby --version  # Should show 3.3.6
```

### 3. Bundler

```bash
gem install bundler
```

### 4. Python 3.12.8

Ubuntu 24.04 ships with Python 3.12.x. Verify:

```bash
python3 --version
```

If you need exactly 3.12.8, use pyenv or mise.

### 5. FFmpeg

```bash
sudo apt-get install -y ffmpeg
```

Or install via your preferred method.

### 6. WhisperX

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
echo 'export PATH="$HOME/.buttercut:$PATH"' >> ~/.bashrc
```

**Option B: Direct pip install**

If you manage Python environments yourself and want whisperx globally available:

```bash
pip install whisperx
```

Ensure `whisperx` is in your PATH.

### 7. ButterCut Ruby Dependencies

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
