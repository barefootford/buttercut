# Library

The `Library` class is the one Ruby class that reads and writes `library.yaml`. The agent drives it through bash:

```bash
ruby lib/buttercut/library.rb <library_name> <action> [args...]
```

## Load-bearing rules

- **Main thread only.** `Library` mutates the shared `library.yaml`;
  sub-agents must never call it (race conditions). Have a sub-agent return
  the data the orchestrator needs and let the orchestrator write.
- **Avoid writing to `library.yaml` directly.** Go through the CLI.
  Only write to library when handling edge cases or failed migrations. 99
  percent of the time the library class should provide what you need.

## Fields and on-disk layout

Completeness tracks three per-video fields. Each field's subdir, filename
pattern, and orphan-sweep filter live in the `FIELDS` table at the top of
`library.rb`:

| Field           | Subdir            | Filename pattern    |
|-----------------|-------------------|---------------------|
| `transcript`    | `transcripts/`    | `<clip>.json`       |
| `contact_sheet` | `contact_sheets/` | `<clip>_full.jpg`   |
| `summary`       | `summaries/`      | `summary_<clip>.md` |

`complete` validates each batch atomically: every clip must exist in
`library.yaml` AND its file must exist on disk before any YAML is written.
If any check fails the call raises and the YAML is left untouched.

The audio transcript JSON is the source of truth for dialogue, and agents that
want clean dialogue text run
`ruby lib/buttercut/script_extractor.rb <transcript>` on demand (stdout).

## CLI

### Discover and check
```bash
ruby lib/buttercut/library.rb list                # every library, newest first by library.yaml mtime
ruby lib/buttercut/library.rb recent [N]          # N most recent libraries by deepest file mtime (default 10)
ruby lib/buttercut/library.rb migrate             # run all migrations across every library (idempotent)
ruby lib/buttercut/library.rb <name> exists       # exit 0 if it exists, 1 if not
ruby lib/buttercut/library.rb <name> summary      # JSON: metadata + clip-completion breakdown
ruby lib/buttercut/library.rb <name> incomplete_videos
ruby lib/buttercut/library.rb <name> ready        # exit 0 if every video is ready for roughcut, 1 if not
ruby lib/buttercut/library.rb update_checked      # record that you just checked GitHub for a newer ButterCut
```

**Daily update-check gate.** The Library class has a once-a-day gate to check
for updates to ButterCut. If in Auto mode, check for updates. Otherwise ask the
user.

`recent` is the right tool for "which library was the user most recently working on?" — it sees activity across `transcripts/`, `contact_sheets/`, `summaries/`, and `cuts/`, not just `library.yaml`. `list` is fine when you want the full set.

`summary` is the snapshot to call when picking up a library — full metadata plus a clip-completion breakdown. `ready` is the one-shot pre-flight before building a cut: it's legacy-aware (a clip with `summary` + either `transcript` or `visual_transcript` counts as ready, even without a `contact_sheet`), so it doesn't block roughcut work on libraries that predate the contact-sheet pipeline. The roughcut sub-agent generates contact sheets on demand when it needs to see a clip.

Use `summary` when you want to look at *what's* missing; use `ready` when you only need a yes/no gate.

### Add and update
```bash
ruby lib/buttercut/library.rb <name> add_videos /abs/a.mov /abs/b.mov
ruby lib/buttercut/library.rb <name> update_metadata footage_summary       "subjects, locations, activities"
ruby lib/buttercut/library.rb <name> update_metadata user_context          "creative intent, characters"
ruby lib/buttercut/library.rb <name> update_metadata language              english
ruby lib/buttercut/library.rb <name> update_metadata editor                fcpx        # fcpx | premiere | resolve
ruby lib/buttercut/library.rb <name> update_metadata transcript_refinement false       # true | false
```

`update_metadata` edits one field per call. Beyond the two free-text fields
(`footage_summary`, `user_context`) it can also set the setup choices
(`language`, `editor`, `transcript_refinement`) — handy when resuming a
library whose config was never filled in. `editor` is validated against
`fcpx|premiere|resolve` and `transcript_refinement` is coerced to a real
boolean.

### Mark files done
```bash
ruby lib/buttercut/library.rb <name> complete <field> <files...>
```

Examples:
```bash
ruby lib/buttercut/library.rb my-lib complete transcript DJI_0123.mov DJI_0124.mov
ruby lib/buttercut/library.rb my-lib complete summary    DJI_0123.mov,DJI_0124.mov
```

`<files>` is space- and/or comma-separated. Call `complete` incrementally
as each batch lands — not in one final sweep — so progress persists if a
later batch fails.

### Destructive resets
```bash
ruby lib/buttercut/library.rb <name> reset <field> [<field>...]
ruby lib/buttercut/library.rb <name> reset_all
ruby lib/buttercut/library.rb <name> reset_all_except_audio_transcripts
ruby lib/buttercut/library.rb <name> remove_visual_transcripts   # legacy cleanup
```

`reset` deletes every file in each named field's subdir and clears the
field on every video. The `transcripts/` sweep leaves `visual_*.json`
alone — that's what `remove_visual_transcripts` is for.

`reset_all` is a **factory reset**: on top of wiping all three artifact
fields it also clears library-level metadata — the setup choices
(`language`, `editor`, `transcript_refinement`) and the analysis-derived
context (`footage_summary`, `user_context`). Strings go blank and
`transcript_refinement` goes nil ("unset"), so a re-run starts setup and
footage analysis from scratch. Video records and dates are kept.
`reset_all_except_audio_transcripts` does **not** touch metadata — it stays
a narrow artifact reset.

### Creating a new library

`Library.create` is the one operation that's kwarg-heavy enough not to map
cleanly to a positional CLI. Invoke it via `ruby -e`:

```bash
ruby -e "require_relative 'lib/buttercut/library'; \
  Library.create('my-lib', \
    language: 'en', \
    editor: 'fcpx', \
    transcript_refinement: true, \
    video_paths: ['/abs/a.mov', '/abs/b.mov'])"
```
