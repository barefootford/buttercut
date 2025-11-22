---
name: backup-library
description: Creates compressed ZIP backups of libraries directory. Backs up library.yaml, transcripts, and roughcuts (not video files). This skill can also be useful when you need to restore a library.
---

# Skill: Backup Library

Verify libraries directory exists:
```bash
ls -la libraries/
```

Run backup:
```bash
ruby .claude/skills/backup-library/backup_libraries.rb
```

Creates `backups/libraries_YYYYMMDD_HHMMSS.zip` containing the entire libraries directory.

## Restore Library

To restore from a backup, extract the ZIP file to the project root.
```bash
unzip backups/libraries_timestamp.zip -d .
```
This restores all libraries to their original locations.
