# Simple Setup (Non-Technical Users)

Fully automatic installation. Run each step in order, waiting for each to complete. Don't move forward until each step is successful. This may be a non-technical user so adjust your explanations accordingly.

**Note:** ButterCut encourages the use of the CPU version of WhisperX only. This simplifies installation and works reliably on all modern Macs with Apple Silicon.

## Step 1: Xcode Command Line Tools

```bash
xcode-select -p 2>/dev/null || xcode-select --install
```

If `xcode-select --install` runs, a GUI dialog appears. **Tell user to click "Install" and wait** (5-10 minutes). Then verify:

```bash
xcode-select -p
```

Should return `/Library/Developer/CommandLineTools` or similar.

## Step 2: Homebrew

```bash
which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After install, add to PATH (Apple Silicon):

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify with `brew --version`. Don't proceed until brew works.

## Step 3: Mise (Version Manager)

```bash
which mise || brew install mise
```

Activate mise in shell profile:

```bash
# Detect shell and add mise activation
if [[ "$SHELL" == *"zsh"* ]]; then
  grep -q 'mise activate' ~/.zshrc 2>/dev/null || echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
  eval "$(mise activate zsh)"
elif [[ "$SHELL" == *"bash"* ]]; then
  grep -q 'mise activate' ~/.bash_profile 2>/dev/null || echo 'eval "$(mise activate bash)"' >> ~/.bash_profile
  eval "$(mise activate bash)"
fi
```

Verify: `mise --version`

## Step 4: Ruby and Python via Mise

From the buttercut directory:

```bash
mise trust
mise install
```

Verify versions:

```bash
ruby --version    # Should show 3.3.6
python3 --version # Should show 3.12.8
```

## Step 5: Bundler

```bash
which bundle || gem install bundler
```

## Step 6: FFmpeg

```bash
which ffmpeg || brew install ffmpeg
```

## Step 7: WhisperX Virtual Environment

```bash
mkdir -p ~/.buttercut

if [ ! -d ~/.buttercut/venv ]; then
  python3 -m venv ~/.buttercut/venv
fi

source ~/.buttercut/venv/bin/activate
pip install --upgrade pip
pip install whisperx
deactivate
```

## Step 8: WhisperX Wrapper Script

```bash
cat > ~/.buttercut/whisperx << 'EOF'
#!/bin/bash
source ~/.buttercut/venv/bin/activate
whisperx "$@"
deactivate
EOF
chmod +x ~/.buttercut/whisperx
```

## Step 9: Add to PATH

```bash
if [[ "$SHELL" == *"zsh"* ]]; then
  grep -q 'buttercut' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.buttercut:$PATH"' >> ~/.zshrc
elif [[ "$SHELL" == *"bash"* ]]; then
  grep -q 'buttercut' ~/.bash_profile 2>/dev/null || echo 'export PATH="$HOME/.buttercut:$PATH"' >> ~/.bash_profile
fi
```

## Step 10: Install ButterCut Dependencies

```bash
bundle install
```

## Final Step

Tell user to open a new terminal window for all changes to take effect.

## Troubleshooting

- **Xcode stuck**: `sudo rm -rf /Library/Developer/CommandLineTools` then retry
- **Homebrew not in PATH**: Run `eval "$(/opt/homebrew/bin/brew shellenv)"`
- **Mise not activating**: Open new terminal, run `mise doctor`
- **Wrong Ruby/Python**: Run `mise trust && mise install` from buttercut directory
- **WhisperX not found**: Ensure `~/.buttercut` is in PATH, open new terminal
- **WhisperX import errors**: The wrapper script handles venv activation automatically; ensure you're using `~/.buttercut/whisperx` not calling whisperx directly
