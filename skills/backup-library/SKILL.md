---
name: backup-library
description: Backs up user libraries and all their contents (external video excluded). This skill can also be useful when you need to restore a library.
---

# Skill: Backup Library

Verify libraries directory exists:
```bash
ls -la libraries/
```

Run backup:
```bash
# Prefer mise if available; fall back to bare ruby otherwise.
mise exec -- ruby .claude/skills/backup-library/backup_libraries.rb
```

Creates `backups/libraries_YYYYMMDD_HHMMSS.aar` when the macOS Apple Archive CLI (`aa`) is available — hardware-accelerated on Apple Silicon, Finder handles double-click extract. Falls back to `.zip` when `aa` is not present.

## Restore Library

Extract to the project root. The command depends on the archive format:

```bash
# Apple Archive
aa extract -i backups/libraries_timestamp.aar -d .

# Zip
unzip backups/libraries_timestamp.zip -d .
```

Either restores all libraries to their original locations.
