# Windows Setup (Non-Technical Users)

Sets up a Windows 10 or 11 PC for ButterCut. Run each step in order, waiting for each to complete. Don't move forward until each step is successful. This may be a non-technical user so adjust your explanations accordingly.

Every install below is per-user via `winget` (Windows' built-in package manager) — no admin password needed on a normal personal PC. winget verifies each package's hash before installing.

**Shell note:** Claude Desktop and Claude Code on Windows run commands through **Git Bash** once Git for Windows is installed (Claude Desktop requires it). Every command below is written for Git Bash — `~` means the user's home folder (`C:\Users\<name>`), and Git Bash converts paths automatically when calling Windows programs. If you find yourself in PowerShell instead (`uname` not found), install Git in Step 1 first, then restart the Claude app completely.

**Requirements:** Windows 10 (version 1909 or later) or Windows 11. Claude Desktop's Cowork mode additionally requires a Pro, Enterprise, or Education edition of Windows (Home lacks the virtualization it needs); Claude Code works on any edition.

## Step 0: Check Install Location

Check the current working directory. Warn if ButterCut is in a problematic location:

**Problematic locations:**
- `~/Desktop/` or `~/Documents/` when OneDrive manages them (path contains `OneDrive`) — sync fights with git and churns on large files
- `~/Downloads/` - Often cleaned up automatically
- Any path containing spaces - Some CLI tools have issues
- Deeply nested folders - Windows path-length limits bite on long clip names

**Recommended location:** `~/code/buttercut` (that's `C:\Users\<name>\code\buttercut`)

If in a problematic location, ask if they'd like to move it. If yes:

1. Run `mkdir -p ~/code`
2. Run `cp -R [current-path] ~/code/buttercut`
3. Tell the user to open `C:\Users\<their name>\code\buttercut` in Claude next time, and to delete the old copy once the new one works.

If they prefer to stay in the current location, continue with setup.

Also guard against long-path errors before they happen (safe, repo-local, no admin):

```bash
git config core.longpaths true
```

## Step 1: Git for Windows

Usually already present — Claude Desktop on Windows requires it. Check:

```bash
git --version
```

If missing:

```bash
winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
```

After installing Git, tell the user to **quit the Claude app completely and reopen it** (see Final Step for how) — the shell only picks up Git when the app starts.

## Step 2: Ruby 3.3 (RubyInstaller with DevKit)

```bash
winget install --id RubyInstallerTeam.RubyWithDevKit.3.3 -e --accept-source-agreements --accept-package-agreements
```

The DevKit variant lets any gem with a native extension build itself; the gems ButterCut uses ship precompiled for Windows, so installs are normally quick.

Open a new shell (or fully restart the Claude app) so PATH updates, then verify:

```bash
ruby --version    # any 3.3.x is fine (.ruby-version pins 3.3.6 for version managers; RubyInstaller may carry a nearby 3.3 patch)
```

## Step 3: Install ButterCut's Ruby Dependencies

From the buttercut directory:

```bash
bundle install
```

(If `bundle` is missing: `gem install bundler`, then retry.)

## Step 4: Python 3.12

```bash
winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
```

Verify in a new shell:

```bash
py -3.12 --version    # Should show Python 3.12.x
```

If a bare `python` opens the Microsoft Store instead of running Python, that's Windows' "App execution alias" shim — just use `py -3.12` everywhere, or turn the aliases off under Settings → Apps → App execution aliases.

## Step 5: FFmpeg (build with drawtext)

ButterCut's contact-sheet pipeline burns timestamps onto frames with the `drawtext` filter, so the build must include it. The Gyan.FFmpeg **full** build does, and winget verifies the package hash:

```bash
winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements
```

Open a new shell, then verify drawtext:

```bash
ffmpeg -hide_banner -filters 2>/dev/null | grep -q ' drawtext ' && echo "drawtext OK"
```

## Step 6: WhisperX Virtual Environment

```bash
mkdir -p ~/.buttercut

if [ ! -d ~/.buttercut/venv ]; then
  py -3.12 -m venv ~/.buttercut/venv
fi

~/.buttercut/venv/Scripts/python.exe -m pip install --upgrade pip
~/.buttercut/venv/Scripts/pip.exe install --only-binary :all: --no-binary antlr4-python3-runtime,docopt \
  'whisperx==3.4.2' 'pyannote-audio==3.4.0'
```

(The versions are pinned to the combination ButterCut is tested against — `pyannote-audio` 4.x breaks whisperx 3.4.2, so don't install newer versions even if pip suggests them. `--only-binary :all:` guarantees prebuilt wheels — nothing compiles on the user's machine; the two `--no-binary` exceptions are pure-Python packages that ship no wheel and build without a compiler. If pip ever fails on some other package, retry without the binary flags only, keeping the version pins, and report which package needed compiling.)

No PATH changes and no wrapper script are needed on Windows: ButterCut looks for `~/.buttercut/venv/Scripts/whisperx.exe` automatically when `whisperx` isn't on PATH. Heads up for the user: the first transcription downloads the speech model (a few hundred MB), so it's slower than the ones after.

## Step 7: Repair the skills link (Windows checkouts)

The repo ships `.claude/skills` and `.agents/skills` as symlinks to the top-level `skills/` folder. A Windows git checkout made without symlink support (the default) turns each into a small **text file**, and then Claude can't see ButterCut's skills. Check:

```bash
test -d .claude/skills && echo "link OK" || echo "link BROKEN"
```

If broken, the clean fix is enabling **Developer Mode** (Settings → Privacy & security → For developers → Developer Mode ON — this is what lets Windows create symlinks without admin), then:

```bash
git config core.symlinks true
rm .claude/skills .agents/skills
git checkout -- .claude/skills .agents/skills
test -d .claude/skills && echo "link OK"
```

If the user can't enable Developer Mode (some work machines), fall back to NTFS junctions and tell git to leave them alone:

```bash
rm .claude/skills
cmd //c "mklink /J .claude\\skills %CD%\\skills"
git update-index --skip-worktree .claude/skills

rm .agents/skills
cmd //c "mklink /J .agents\\skills %CD%\\skills"
git update-index --skip-worktree .agents/skills
```

(Junctions store an absolute path — if the ButterCut folder ever moves, re-run this step. `--skip-worktree` keeps `git status` and updates clean despite the local replacement.)

## Step 8: Record how this PC was set up

Agentic clients don't always see the same PATH the user's shells do, so leave a breadcrumb recording absolute invocations that work regardless. Resolve the real paths:

```bash
RUBY_W=$(cygpath -w "$(command -v ruby)")
PYTHON_W=$(cygpath -w "$(py -3.12 -c 'import sys; print(sys.executable)')")
WHISPERX_W=$(cygpath -w ~/.buttercut/venv/Scripts/whisperx.exe)
FFMPEG_W=$(cygpath -w "$(command -v ffmpeg)")
```

Then write `.buttercut_env` in the repo root with those resolved values:

```
# How ButterCut was installed on this PC (written by the setup skill).
# These invocations work even in shells that didn't pick up PATH changes.
# Read this when a tool isn't found or resolves to the wrong version.
ruby     = <resolved ruby path>
python   = <resolved python path>
whisperx = <resolved whisperx path>
ffmpeg   = <resolved ffmpeg path>
```

Keep it to these four lines — it's a breadcrumb, not a config file. `.buttercut_env` is gitignored and machine-specific; never commit it.

## Final Step

For all changes to take effect, tell the user to fully restart whatever they're running ButterCut in:

- **Claude Desktop** — quit it completely (right-click the Claude icon in the system tray, near the clock, and choose Quit — closing the window isn't enough), then reopen it. A new chat alone isn't enough.
- **Terminal / CLI** — open a new terminal window (or restart the terminal app).

## Troubleshooting

- **`winget` not found**: Install "App Installer" from the Microsoft Store (ships with Windows 10 1809+ / all Windows 11), or download installers directly: rubyinstaller.org (Ruby+Devkit 3.3), python.org (3.12), gyan.dev/ffmpeg (full build)
- **Tool installed but not found**: PATH is read when the app starts — fully quit and reopen Claude Desktop (or open a new terminal)
- **`python` opens the Microsoft Store**: use `py -3.12`, or disable the alias under Settings → Apps → App execution aliases
- **`bundle install` compiles forever or fails**: make sure the Ruby install was the **WithDevKit** package; re-run the Step 2 winget command
- **pip SSL or proxy errors**: corporate machines often route traffic through a proxy — ask the user if they're on a work machine and relay the error to IT if so
- **OneDrive churn during processing**: if the ButterCut folder lives under OneDrive, pause syncing while footage processes, or move the folder per Step 0
- **Filename too long errors from git**: re-run `git config core.longpaths true` inside the buttercut folder
- **WhisperX import errors**: the pinned combination above is the tested one; recreate the venv (`rm -rf ~/.buttercut/venv`) and redo Step 6
