# ButterCut on Windows 10/11

Status: **beta**. The Ruby layer is cross-platform and covered by specs; the setup flow and skills carry Windows branches. This page is the developer-facing map of what Windows support consists of and what still needs a hands-on pass.

## The environment ButterCut runs in on Windows

- **Claude Desktop (Cowork)** runs commands natively against the Windows filesystem. It requires **Git for Windows**, and with it present the working shell is **Git Bash** — which is why ButterCut's skills stay bash-first on both platforms. Cowork needs Windows 10 1909+ or 11, Pro/Enterprise/Education edition (Home lacks the required virtualization).
- **Claude Code CLI** works on any Windows edition (10 1809+). With Git for Windows its Bash tool is Git Bash; without it, commands run in PowerShell — ButterCut's setup installs Git first for exactly this reason.
- Skills resolve through `.claude/skills`, a symlink to `skills/` — see link repair below.

## What was made cross-platform

- `lib/buttercut/platform.rb` — the one owner of OS detection, PATH/`.exe` resolution, open-with-default-app argv, ffmpeg hwaccel choice, filter-path escaping, and the System32 bsdtar / PowerShell locations. Everything else in `lib/` asks it.
- **No shell-quoted subprocesses left** — every ffprobe/ffmpeg/xmllint call is argv-form `Open3`, so media paths never meet sh vs. cmd.exe quoting.
- **WhisperX resolution** falls back from PATH to the `~/.buttercut` venv entry points (`Scripts/whisperx.exe` on Windows, `bin/whisperx` elsewhere).
- **Contact sheets** try D3D11VA hardware decode on Windows (videotoolbox on macOS) with the existing software fallback.
- **Exports** write drive-letter paths as the Premiere-style `file://localhost/C%3a/...` form and put UNC servers in the URL authority; POSIX output is byte-identical to before.
- **Backups** fall back from the `zip` CLI (absent on Windows) to System32 bsdtar, then PowerShell `Compress-Archive`.
- **Settings** default the editor to `resolve` on Windows (Final Cut doesn't exist there); the **Preview** app opens the browser via `cmd /c start`.
- Setup: `skills/setup/windows-setup.md` (winget installs, WhisperX venv, link repair, `.buttercut_env`), `scripts/keep_awake.ps1` (the `caffeinate` equivalent), Windows branches in the skills that touched macOS-only tools, and a Platforms section in AGENTS.md. `Gemfile.lock` carries `x64-mingw-ucrt` so `bundle install` resolves on RubyInstaller.

## Windows checkout link repair (`.claude/skills`)

A Windows clone without symlink support (the git default there) materializes `.claude/skills` and `.agents/skills` as small text files, and Claude can't see the skills. Two repairs, documented in `windows-setup.md`: enable Developer Mode + `git config core.symlinks true` + re-checkout (preferred), or NTFS junctions (`mklink /J`) with `git update-index --skip-worktree`.

## Remaining work

1. **Flip the Windows CI job to blocking.** `.github/workflows/ci.yml`'s `test-windows` job is `continue-on-error: true` for now: a few specs still assert POSIX-shaped absolute paths (`/tmp/...` file URLs) and need platform-aware expectations before the job can gate merges.
2. **Hands-on import validation.** The `file://localhost/C%3a/...` pathurl form is what Premiere and Resolve themselves write on Windows (verified against real exports of both), and unit tests lock it in — but ButterCut's own output hasn't been imported on a real Windows machine yet. Matrix to run, in both Premiere and Resolve (pass = clips link with no relink dialog, correct durations, audio present): a `C:` path with spaces and parens; a non-ASCII filename; a second drive letter; a UNC `\\server\share` path (weakest evidence — if it fails, document mapped-drive letters as the fallback); a OneDrive-relocated Desktop path. Also still pending: a real end-to-end library on Windows (WhisperX CPU, contact sheets, D3D11VA fallback on GPU-less machines).
3. **Pinned static FFmpeg for Windows.** macOS installs pinned, checksum-verified static builds into `dependencies/` (`scripts/install_ffmpeg.sh`); Windows relies on winget's hash-verified `Gyan.FFmpeg` build for now. A Windows counterpart installing into `dependencies\` (MediaTools already resolves `dependencies/ffmpeg.exe`) is worth adding once builds are pinned.
4. **Long-running transcription under Claude Desktop.** Reports exist of Windows Claude Desktop killing idle background tasks after ~15 minutes. Processing is resumable by design (library.yaml is the ledger), so re-running finishes what's left — but if it bites often, consider chunking the transcript step per-clip from the skill.
5. **`update-buttercut` on Windows** should re-verify the `.claude/skills` link after a pull (a pull can re-materialize it as a text file on non-Developer-Mode machines).
6. **GPU transcription — deliberately not offered.** Transcription is CPU-only on every platform. The stock pinned install cannot use CUDA on any card: PyPI torch wheels on Windows are CPU-only, and WhisperX 3.4.2 pins ctranslate2 to a cuDNN-8 line against a cuDNN-9 torch ([whisperX#1216](https://github.com/m-bain/whisperX/issues/1216)) — GPU requires rebuilding the venv's torch stack by hand (one field-verified expert stack is catalogued in [buttercut#132](https://github.com/barefootford/buttercut/issues/132)). Revisit when ButterCut's pinned WhisperX moves to the 3.8.x line (ctranslate2≥4.5, pyannote 4.x), which resolves the conflict and makes a supported settings.yaml opt-in realistic.
7. **Extend `.claude/settings.json` permission allows for Windows tooling** (a human product decision). Narrow adds: `Bash(uname:*)`, `Bash(cygpath:*)`, `Bash(explorer:*)`, `Bash(tar:*)`, `Bash(py:*)`, `Bash(winget:*)`. Broader, worth a deliberate call: `Bash(powershell:*)` and `Bash(cmd:*)` — needed friction-free for `keep_awake.ps1`, the Compress-Archive fallback, and the junction repair, but they're arbitrary-execution grants, same class as the existing `Bash(ruby:*)`.
