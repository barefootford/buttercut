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

## Media types

A library's `media:` array holds two kinds of entry, keyed by file extension
(the type is inferred, never stored). The `MEDIA_TYPES` registry at the top of
`library.rb` is the single owner of what's accepted and which fields apply:

| Type    | Extensions                         | Per-clip fields                      | Duration probed? |
|---------|------------------------------------|--------------------------------------|------------------|
| `video` | `mov mp4 mts m2ts mxf avi`         | `transcript`, `contact_sheet`, `summary` | yes          |
| `image` | `jpg jpeg png`                     | `summary` only                       | no               |

The extension sets are a closed allowlist — the intersection of what Final Cut,
Premiere, and Resolve all import natively (see "Supported media formats" in
`AGENTS.md`). `add_media`/`create` reject anything outside it; **reads stay
lenient** (an odd extension already in the yaml reads as video). Everything
type-aware — `ready?`, `pending`, `incomplete_media`, `complete!`, `reset!` —
is driven off this registry, so adding a media type is one registry entry, not a
code audit. (ButterCut Pro extends the registry in its fork, e.g. an `audio`
entry.)

## Fields and on-disk layout

Each field's subdir, filename pattern, and orphan-sweep filter live in the
`FIELDS` table at the top of `library.rb`:

| Field           | Subdir            | Filename pattern    |
|-----------------|-------------------|---------------------|
| `transcript`    | `transcripts/`    | `<clip>.json`       |
| `contact_sheet` | `contact_sheets/` | `<clip>_full.jpg`   |
| `summary`       | `summaries/`      | `summary_<clip>.md` |

Artifact filenames are built from a **clip key**: for videos the extension is
stripped (`P1055017.mov` → `P1055017`, matching every existing artifact on
disk); for images the extension is flattened in (`DJI_0123.jpg` →
`DJI_0123_jpg`) so a photo and a video that share a basename — common with
drones and mirrorless stills — can't collide on artifact names.

`complete` validates each batch atomically: every clip must exist in
`library.yaml` AND its file must exist on disk before any YAML is written, and
the field must apply to the clip's type (e.g. `transcript` on an image raises).
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
ruby lib/buttercut/library.rb <name> summary      # JSON: metadata + per-type counts + clip-completion breakdown
ruby lib/buttercut/library.rb <name> incomplete_media
ruby lib/buttercut/library.rb <name> unsupported_media   # JSON: entries whose extension no editor imports natively
ruby lib/buttercut/library.rb <name> ready        # exit 0 if every clip is ready for a cut, 1 if not
ruby lib/buttercut/library.rb update_checked      # record that you just checked for a newer ButterCut
ruby lib/buttercut/library.rb edition             # print which ButterCut edition this is (core or pro)
```

**Daily update-check gate.** The Library class has a once-a-day gate to check
for updates to ButterCut. If in Auto mode, check for updates. Otherwise ask the
user.

`recent` is the right tool for "which library was the user most recently working on?" — it sees activity across `transcripts/`, `contact_sheets/`, `summaries/`, and `cuts/`, not just `library.yaml`. `list` is fine when you want the full set.

`summary` is the snapshot to call when picking up a library — full metadata, a `media_count` with a per-type breakdown (`video_count`, `image_count`), and a clip-completion list. `ready` is the one-shot pre-flight before building a cut: it's type- and legacy-aware (a video with `summary` + either `transcript` or `visual_transcript` counts as ready even without a `contact_sheet`; an image just needs its `summary`), so it doesn't block cut work on libraries that predate the contact-sheet pipeline. The cut sub-agent generates contact sheets on demand when it needs to see a clip.

Use `summary` when you want to look at *what's* missing; use `ready` when you only need a yes/no gate.

### Add and update
```bash
ruby lib/buttercut/library.rb <name> add_media    /abs/a.mov /abs/photo.jpg   # type inferred from extension
ruby lib/buttercut/library.rb <name> remove_media a.mov                       # drop entry + its artifacts; source file untouched
ruby lib/buttercut/library.rb <name> update_metadata footage_summary       "subjects, locations, activities"
ruby lib/buttercut/library.rb <name> update_metadata user_context          "creative intent, characters"
ruby lib/buttercut/library.rb <name> update_metadata language              english
ruby lib/buttercut/library.rb <name> update_metadata editor                fcpx        # fcpx | premiere | resolve
ruby lib/buttercut/library.rb <name> update_metadata transcript_refinement false       # true | false
```

`add_media` appends videos and images alike — the type (and therefore which
per-clip fields the entry gets) is inferred from each path's extension; an
unsupported extension is rejected with a message naming the supported sets.
`remove_media` drops an entry and deletes its artifacts (transcripts, contact
sheets, summaries, plus any legacy visual transcript) but **never** touches the
source footage on disk.

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
field on every clip that has it. The `transcripts/` sweep leaves `visual_*.json`
alone — that's what `remove_visual_transcripts` is for.

`reset_all` is a **factory reset**: on top of wiping all three artifact
fields it also clears library-level metadata — the setup choices
(`language`, `editor`, `transcript_refinement`) and the analysis-derived
context (`footage_summary`, `user_context`). Strings go blank and
`transcript_refinement` goes nil ("unset"), so a re-run starts setup and
footage analysis from scratch. Media records and dates are kept.
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
    media_paths: ['/abs/a.mov', '/abs/photo.jpg'])"
```

`media_paths` takes videos and images alike — each entry is scaffolded with the
fields its type needs (videos get `transcript`/`contact_sheet`/`summary` and a
probed duration; images get just `summary`).
