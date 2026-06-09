# Simple Setup (Non-Technical Users)

Fully automatic installation. Run each step in order, waiting for each to complete. Don't move forward until each step is successful. This may be a non-technical user so adjust your explanations accordingly.

**Note:** ButterCut encourages the use of the CPU version of WhisperX only. This simplifies installation and works reliably on all modern Macs with Apple Silicon.

## Step 0: Check Install Location

Check the current working directory. Warn if ButterCut is in a problematic location:

**Problematic locations:**
- `~/Desktop/` - Desktop gets cluttered, easy to accidentally delete
- `~/Downloads/` - Often cleaned up automatically
- `~/Library/Mobile Documents/` (iCloud) - Sync causes issues with git and large files
- Any path containing spaces - Some CLI tools have issues

**Recommended locations:**
- `~/code/buttercut`
- `~/projects/buttercut`

If in a problematic location, ask if they'd like to move it. If yes:

1. Run `mkdir -p ~/code` (or `~/projects` if that exists)
2. Run `cp -R [current-path] ~/code/buttercut`
3. Tell the user:
   ```
   I've copied ButterCut to ~/code/buttercut. To finish:
   1. Delete [current-path] (drag to Trash)
   2. Run this in Terminal: cd ~/code/buttercut && claude
   ```

If they prefer to stay in the current location, continue with setup.

## Step 1: Xcode Command Line Tools

```bash
xcode-select -p 2>/dev/null || xcode-select --install
```

If `xcode-select --install` runs, a GUI dialog appears. **Tell user to click "Install" and wait** (5-10 minutes). Then verify:

```bash
xcode-select -p
```

Should return `/Library/Developer/CommandLineTools` or similar.

## Step 2: Homebrew (Manual Installation Required)

Check if Homebrew is installed:

```bash
which brew
```

If not installed, **tell the user to run the install command themselves**. Homebrew requires interactive terminal access (password prompts, confirmations) and cannot be installed by the agent directly.

Tell the user to run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Wait for the user to confirm installation is complete before continuing.

After install, add to PATH (Apple Silicon):

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify with `brew --version`. Don't proceed until brew works.

Install libyaml (required for Ruby's psych extension):

```bash
brew install libyaml
```

## Step 3: Mise (Version Manager)

```bash
which mise || brew install mise
```

If mise is already installed, make sure it's at least version 2025.12.4 (the release that added precompiled Ruby support):

```bash
mise --version
brew upgrade mise   # run if version is older than 2025.12.4
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

Mise downloads precompiled Ruby and Python binaries (configured in `.mise.toml`), so this typically finishes in under a minute. If a precompiled binary isn't available for the pinned version, mise falls back to building from source, which can take 5-10 minutes.

Verify versions:

```bash
ruby --version    # Should show 3.3.6
python3 --version # Should show 3.12.8
```

## Step 5: FFmpeg (full build with drawtext)

ButterCut's contact-sheet pipeline burns timestamps onto frames with the `drawtext` filter. The stock `brew install ffmpeg` formula often ships without `drawtext` enabled, so we install the full build from the `homebrew-ffmpeg/ffmpeg` tap and make it the only ffmpeg on the machine.

If the stock formula is already installed, remove it first so the tap version links cleanly:

```bash
brew list ffmpeg >/dev/null 2>&1 && brew uninstall --ignore-dependencies ffmpeg || true
```

Install the tap build:

```bash
brew tap homebrew-ffmpeg/ffmpeg
brew install homebrew-ffmpeg/ffmpeg/ffmpeg
brew link --overwrite homebrew-ffmpeg/ffmpeg/ffmpeg
```

Verify drawtext is present (must print a line containing `drawtext`):

```bash
ffmpeg -hide_banner -filters 2>/dev/null | grep ' drawtext '
```

If nothing prints, the install didn't pick up libfreetype — re-run the tap install and re-verify before continuing.

## Step 6: WhisperX Virtual Environment

```bash
mkdir -p ~/.buttercut

if [ ! -d ~/.buttercut/venv ]; then
  python3 -m venv ~/.buttercut/venv
fi

source ~/.buttercut/venv/bin/activate
pip install --upgrade pip
pip install 'whisperx==3.4.2' 'pyannote-audio==3.4.0'
deactivate
```

(The versions are pinned to the combination ButterCut is tested against — `pyannote-audio` 4.x breaks whisperx 3.4.2, so don't install newer versions even if pip suggests them.)

## Step 7: WhisperX Wrapper Script

```bash
cat > ~/.buttercut/whisperx << 'EOF'
#!/bin/bash
source ~/.buttercut/venv/bin/activate
whisperx "$@"
deactivate
EOF
chmod +x ~/.buttercut/whisperx
```

## Step 8: Add to PATH

```bash
if [[ "$SHELL" == *"zsh"* ]]; then
  grep -q 'buttercut' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/.buttercut:$PATH"' >> ~/.zshrc
elif [[ "$SHELL" == *"bash"* ]]; then
  grep -q 'buttercut' ~/.bash_profile 2>/dev/null || echo 'export PATH="$HOME/.buttercut:$PATH"' >> ~/.bash_profile
fi
```

## Step 9: Install ButterCut Dependencies

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
