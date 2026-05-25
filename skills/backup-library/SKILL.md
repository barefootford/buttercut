---
name: backup-library
description: Backs up user libraries and all their contents (external video excluded). This skill can also be useful when you need to restore a library.
---

# Skill: Backup Library

Backups default to `~/Documents/buttercut-video-editor-backups`. Each library gets its own subdirectory there, and each run drops a timestamped archive of just that one library — so adding a new clip to one library only writes that library's archive, not a full duplicate of everything.

```
~/Documents/buttercut-video-editor-backups/
  wedding/
    wedding_20260520_140000.aar
  programmer-story-vlog/
    programmer-story-vlog_20260520_140000.aar
```

## Step 1 — Resolve the destination

Read `backups_dir` from `libraries/settings.yaml`. If the key is missing, ask the user with `AskUserQuestion` whether to use the default (`~/Documents/buttercut-video-editor-backups`, recommended) or a custom folder, and save the answer to `libraries/settings.yaml` under `backups_dir`. If `libraries/settings.yaml` doesn't exist yet, create it from `templates/settings_template.yaml` first.

When invoked from another skill that must stay non-interactive (e.g. `process-library` auto-backup) and `backups_dir` isn't set, skip the prompt and use the default — the user can change it later.

## Step 2 — Run the backup

Default to backing up just the library you've been working on — that's almost always what "run a backup" means. Only back up everything when the user explicitly asks for "all libraries" or you're doing a one-time cleanup pass.

```bash
# Back up the one library you just touched (the usual case)
ruby lib/buttercut/backup_libraries.rb --library <library-name>

# Back up every library (only when the user explicitly asks)
ruby lib/buttercut/backup_libraries.rb
```

The script reads `backups_dir` from `libraries/settings.yaml` (falling back to the default). Pass `--backups-dir <path>` to override for one run.

Apple Archive (`.aar`) is used when the macOS `aa` CLI is available — hardware-accelerated on Apple Silicon, Finder handles double-click extract. Falls back to `.zip` otherwise.

After a successful `backup_all` run, the script removes the legacy in-project `backups/` directory (the old single-archive layout) if it still exists and the resolved `backups_dir` is somewhere else. Per-library runs leave it alone.

## Restore a library

Extract the per-library archive back into `libraries/`:

```bash
# Apple Archive — restores into libraries/<library-name>/
aa extract -i ~/Documents/buttercut-video-editor-backups/<library>/<library>_<timestamp>.aar -d libraries/<library>

# Zip — already contains the <library>/ folder
unzip ~/Documents/buttercut-video-editor-backups/<library>/<library>_<timestamp>.zip -d libraries/
```
