# Simple Setup (Non-Technical Users)

Fully automatic installation for Ubuntu 24.04. Run each step in order, waiting for each to complete.

**Note:** ButterCut uses the CPU version of WhisperX. This simplifies installation and works reliably without GPU setup.

## Step 0: Check Install Location

Check the current working directory. Warn if ButterCut is in a problematic location:

**Problematic locations:**
- `~/Desktop/` - Desktop gets cluttered, easy to accidentally delete
- `~/Downloads/` - Often cleaned up automatically
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
   1. Delete [current-path]
   2. Run this in Terminal: cd ~/code/buttercut && claude
   ```

If they prefer to stay in the current location, continue with setup.

## Step 1: System Build Dependencies

Install required libraries for building Ruby and running ButterCut. **User must run this** (requires sudo):

Tell the user to run:

```bash
sudo apt-get install -y libyaml-dev libssl-dev libreadline-dev zlib1g-dev libxml2-utils
```

Wait for the user to confirm before continuing.

## Step 2: Mise (Version Manager)

```bash
curl https://mise.run | sh
```

Activate mise in shell profile:

```bash
if [[ "$SHELL" == *"zsh"* ]]; then
  grep -q 'mise activate' ~/.zshrc 2>/dev/null || echo 'eval "$($HOME/.local/bin/mise activate zsh)"' >> ~/.zshrc
  eval "$($HOME/.local/bin/mise activate zsh)"
elif [[ "$SHELL" == *"bash"* ]]; then
  grep -q 'mise activate' ~/.bashrc 2>/dev/null || echo 'eval "$($HOME/.local/bin/mise activate bash)"' >> ~/.bashrc
  eval "$($HOME/.local/bin/mise activate bash)"
fi
```

Verify: `~/.local/bin/mise --version`

## Step 3: Ruby and Python via Mise

From the buttercut directory:

```bash
~/.local/bin/mise trust
~/.local/bin/mise settings ruby.compile=false
~/.local/bin/mise install
```

Verify versions:

```bash
ruby --version    # Should show 3.3.6
python3 --version # Should show 3.12.8
```

## Step 4: Bundler

```bash
which bundle || gem install bundler
```

## Step 5: FFmpeg

Check if already installed:

```bash
which ffmpeg
```

If not installed, tell the user to run:

```bash
sudo apt-get install -y ffmpeg
```

## Step 6: WhisperX Virtual Environment

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
  grep -q 'buttercut' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/.buttercut:$PATH"' >> ~/.bashrc
fi
```

## Step 9: Install ButterCut Dependencies

```bash
bundle install
```

## Final Step

Tell user to open a new terminal window for all changes to take effect.

## Troubleshooting

- **libyaml not found during Ruby build**: Ensure `sudo apt-get install -y libyaml-dev` completed successfully
- **Mise not activating**: Open new terminal, run `~/.local/bin/mise doctor`
- **Wrong Ruby/Python**: Run `~/.local/bin/mise trust && ~/.local/bin/mise install` from buttercut directory
- **WhisperX not found**: Ensure `~/.buttercut` is in PATH, open new terminal
- **WhisperX import errors**: The wrapper script handles venv activation automatically; ensure you're using `~/.buttercut/whisperx` not calling whisperx directly
- **FFmpeg not found**: Run `sudo apt-get install -y ffmpeg`
