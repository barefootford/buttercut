# When footage isn't where the library expects it

`verify_media` reported `missing` or `phantom` clips. Don't export against them — a
cut that references files the editor can't find imports as offline (red) media.
Reconnect the footage first, then re-verify and export.

## What the statuses mean

- `missing` — the file isn't at its stored path. Usually the drive is unplugged, or
  it remounted under a new name (macOS mounts a drive whose name is squatted by a
  leftover folder as `<name> 1` — e.g. `MyDrive` becomes `MyDrive 1`).
- `phantom` — the path *does* resolve, but to a leftover `/Volumes/<name>` folder on
  the internal boot disk rather than the real drive. This is the dangerous one: the
  files there may be a stale or partial copy made while the drive was unplugged, so a
  plain "does it exist?" check is fooled.

## Fixing missing footage (the common case)

1. Ask the user to plug in or remount the drive, then re-run `verify_media`.
2. If it still misses and the report has a `suggested_relinks` entry, the drive
   likely remounted under a new name. Show the user the mapping (e.g.
   `/Volumes/MyDrive` → `/Volumes/MyDrive 1`) and, **only after they confirm**, run:
   ```bash
   ruby lib/buttercut/library.rb <name> relink <old_prefix> <new_prefix>
   ```
   Then re-run `verify_media` to confirm everything is `ok` before exporting.

**Never relink automatically.** Paths are the user's data; a silent rewrite could
point the library at a divergent copy of the footage.

## Fixing a phantom volume

When the report lists `phantom_volumes`, a leftover `/Volumes/<name>` folder on the
internal disk is squatting the drive's real name. The clean fix is to eject the
drive, delete that folder, and remount so the drive reclaims its name.

**Look inside the folder before deleting it.** If it holds files, that's footage
someone rescued there while the drive was unplugged — not junk. Surface it to the
user and let them decide; never delete a non-empty phantom folder.
