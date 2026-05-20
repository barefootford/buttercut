# buttercut-lib

Cross-skill support code for ButterCut. Not a skill itself — has no `SKILL.md`
and won't be discovered by Claude Code, Codex, or other agentic tools as one.

Currently contains a single file: `library.rb`, the `Library` handle for
reading and writing `library.yaml`. The agent drives it through bash:

```bash
ruby skills/buttercut-lib/library.rb <library_name> <action> [args...]
```

## Load-bearing rules

- **Main thread only.** `Library` mutates the shared `library.yaml`;
  sub-agents must never call it (race conditions). Have a sub-agent return
  the data the orchestrator needs and let the orchestrator write.
- **Never read or write `library.yaml` directly.** Go through the CLI.
  If you need an operation it doesn't expose, extend the CLI rather than
  parsing the YAML inline.

## Fields and on-disk layout

Completeness tracks four per-video fields. Each field's subdir, filename
pattern, and orphan-sweep filter live in the `FIELDS` table at the top of
`library.rb`:

| Field           | Subdir            | Filename pattern    |
|-----------------|-------------------|---------------------|
| `transcript`    | `transcripts/`    | `<clip>.json`       |
| `contact_sheet` | `contact_sheets/` | `<clip>_full.jpg`   |
| `script`        | `scripts/`        | `script_<clip>.txt` |
| `summary`       | `summaries/`      | `summary_<clip>.md` |

`complete` validates each batch atomically: every clip must exist in
`library.yaml` AND its file must exist on disk before any YAML is written.
If any check fails the call raises and the YAML is left untouched.

## CLI

### Discover and check
```bash
ruby skills/buttercut-lib/library.rb list                # one library name per line, newest first
ruby skills/buttercut-lib/library.rb <name> exists       # exit 0 if it exists, 1 if not
ruby skills/buttercut-lib/library.rb <name> summary      # JSON: metadata + clip-completion breakdown
ruby skills/buttercut-lib/library.rb <name> incomplete_videos
ruby skills/buttercut-lib/library.rb <name> processed    # exit 0 if every video is processed, 1 if not
```

`summary` is the snapshot to call first when picking up a library —
`incomplete_count == 0` means ready for roughcut.

### Add and update
```bash
ruby skills/buttercut-lib/library.rb <name> add_videos /abs/a.mov /abs/b.mov
ruby skills/buttercut-lib/library.rb <name> update_metadata footage_summary "subjects, locations, activities"
ruby skills/buttercut-lib/library.rb <name> update_metadata user_context   "creative intent, characters"
```

### Mark files done
```bash
ruby skills/buttercut-lib/library.rb <name> complete <field> <files...>
```

Examples:
```bash
ruby skills/buttercut-lib/library.rb my-lib complete transcript DJI_0123.mov DJI_0124.mov
ruby skills/buttercut-lib/library.rb my-lib complete summary    DJI_0123.mov,DJI_0124.mov
```

`<files>` is space- and/or comma-separated. Call `complete` incrementally
as each batch lands — not in one final sweep — so progress persists if a
later batch fails.

### Destructive resets
```bash
ruby skills/buttercut-lib/library.rb <name> reset <field> [<field>...]
ruby skills/buttercut-lib/library.rb <name> reset_all
ruby skills/buttercut-lib/library.rb <name> reset_all_except_audio_transcripts
ruby skills/buttercut-lib/library.rb <name> remove_visual_transcripts   # legacy cleanup
```

`reset` deletes every file in each named field's subdir and clears the
field on every video. The `transcripts/` sweep leaves `visual_*.json`
alone — that's what `remove_visual_transcripts` is for.

### Creating a new library

`Library.create` is the one operation that's kwarg-heavy enough not to map
cleanly to a positional CLI. Invoke it via `ruby -e`:

```bash
ruby -e "require_relative 'skills/buttercut-lib/library'; \
  Library.create('my-lib', \
    language: 'en', \
    editor: 'fcpx', \
    transcript_refinement: true, \
    video_paths: ['/abs/a.mov', '/abs/b.mov'])"
```
