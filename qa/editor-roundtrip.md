# Editor round-trip QA — import the exports into the real editors

Integration tests for the one promise ButterCut can't verify in RSpec: that the
XML we export actually **imports into Final Cut Pro, DaVinci Resolve, and
Premiere and builds the timeline the cut described** — right clips, right
order, right trims, frame-accurately.

**Developer-only.** Run this in a `*-developer` checkout (`.buttercut_mode`
present) on a Mac with the editors installed. It never belongs in a video
editor's session, and it can't run in CI (no editors there). Run it before a
release and after touching anything in the export pipeline (`lib/buttercut/
export*.rb`, `editor_base*`, `fcpx*`, `fcp7*`, `premiere.rb`, `resolve.rb`) or
timecode/frame-rate math.

Both editions carry this suite unchanged — run it in `buttercut-developer` and
`buttercut-pro-developer` separately. The fixture library is gitignored and
regenerated per run, so the clones never share state.

## How it verifies (the trick)

The fixture footage is **self-identifying**: every frame of every synthetic
clip burns in its clip letter, source timecode, and source frame number over a
solid per-clip color, and each clip has a distinct per-second beep pattern so
even the audio waveforms are tellable apart on sight. Ground truth lives in
the pixels, not in metadata — a bug that inserts the wrong clip (or the right
clip at the wrong offset) cannot look correct, because the frame on screen
literally names the source position it came from.

On top of that, the expected timelines are computed with plain arithmetic from
literal tables (`qa/scripts/generate_qa_fixture.rb`), deliberately **not**
with `lib/buttercut`'s own timecode math, so an exporter bug can't cancel
itself out in the expectation. Trims are written in frames — the native unit —
so the math stays exact even at fractional NTSC rates.

## Scenarios

The suite is a matrix of scenario cuts × editors. Tiers: `:fast` scenarios run
on every `run_all.rb`; `:full` scenarios join in with `--full` (run the full
tier before merging anything that touches the export pipeline or timecode
math). The registry lives in `qa_helpers.rb` (names + tiers); each scenario's
definition lives in the generator's literal tables.

| Scenario | Tier | Timeline | Covers |
|---|---|---|---|
| canonical-30 | fast | 30 fps 1280×720 | trims, mute, a held still, out-of-order sources |
| ntsc-2997-df | full | 29.97 | drop-frame embedded timecode starting 2 frames before the 01:00:00 skip (qa_ntscD), NDF timecode at the same fractional rate (qa_ntscE), same source used twice |
| film-23976 | full | 23.976 | embedded SMPTE start `21:44:10:09` (qa_filmF — the `base_timecode + in_point` anchoring with a non-zero base), a no-timecode source at a fractional rate, an in-point of 0 |

The canonical cut (30 fps, 1280×720, 690 frames total):

| # | Source          | Timeline frames | Source frames | Notes            |
|---|-----------------|-----------------|---------------|------------------|
| 1 | qa_clipB.mov    | 0–180           | 300–480       | green, double beeps |
| 2 | qa_clipA.mov    | 180–300         | 60–180        | red, **muted**   |
| 3 | qa_title_card.png | 300–450       | —             | yellow still, 5 s |
| 4 | qa_clipC.mov    | 450–690         | 15–255        | blue, long beeps |

These tables are illustrative snapshots — the generator's literal tables own
the numbers. After a run, the generated `expected_<scenario>.json` and
`expected_visuals.md` in the fixture library are canonical; if you extend the
fixture, don't hand-sync these tables.

How the embedded-timecode scenarios verify: ButterCut anchors each FCPXML clip
at `asset start timecode + in-point`, while FCP's re-export carries FCP's
*own* reading of the media's timecode in the asset's `start`. The FCP verifier
subtracts the two, so a ButterCut base-timecode bug (wrong drop-frame
subtraction, wrong rate) shows up as a source_in/source_out frame mismatch.
The FCP7 XML legs check the file-relative `<in>/<out>` frames plus the
separately-written `<timecode><frame>` base.

## Tier 1 — deterministic run (no tokens, no eyeballs)

From the repo root:

```bash
ruby qa/scripts/run_all.rb           # fast tier: the canonical scenario
ruby qa/scripts/run_all.rb --full    # every scenario in the matrix
```

That regenerates the fixture (`libraries/qa-editor-roundtrip/`), exports every
scenario in all three formats through the shipped CLI
(`lib/buttercut/export.rb`, which also DTD-validates the FCPXML), then runs
one verifier per installed editor per scenario and prints a PASS/FAIL matrix.
Individual legs (no args = the canonical scenario; pass an export + expected
pair for any other):

```bash
ruby qa/scripts/verify_resolve.rb    # DaVinci Resolve
ruby qa/scripts/verify_fcp.rb        # Final Cut Pro
ruby qa/scripts/verify_premiere.rb   # Premiere
ruby qa/scripts/verify_fcp.rb \
  libraries/qa-editor-roundtrip/cuts/ntsc-2997-df_fcpx.fcpxml \
  libraries/qa-editor-roundtrip/expected_ntsc-2997-df.json
```

Each leg imports the export into a scratch project/library inside the real
editor, extracts what the editor actually built, normalizes it, and compares
against the scenario's `expected_<scenario>.json` with
`qa/scripts/compare_timeline.rb` (exact frame equality). The normalized dump
is written next to the exports as `cuts/qa-actual_<scenario>_<editor>.json`
for debugging.

Runtime note: legs currently run once per scenario, so `--full` costs roughly
one FCP round trip (~30 s) plus one Resolve import plus one full Premiere
launch (~60 s) per scenario. When the matrix grows past a handful of
scenarios, batch per editor — one Premiere launch importing every XML into
one scratch project, one Resolve menu click walking a job list — before
adding more cuts.

| Leg | Mechanism | Checks | Can't observe |
|---|---|---|---|
| Resolve | In-app Lua script (`Workspace > Scripts > ButterCut QA Dump`, auto-installed to `~/Library/…/Fusion/Scripts/Utility/`, menu-clicked via System Events). Works on the free edition, where external scripting is unavailable. Imports into a scratch `buttercut-qa-<epoch>` project; previous ones are deleted. | fps, resolution, total length, per-clip record/source frame ranges, media paths, still handling | mute (API doesn't expose levels) |
| Final Cut Pro | UI-driven round trip via System Events: `open` the .fcpxml → in the "Open Library" dialog use **New…** (never the library list — deterministic destination) → creates `buttercut-qa-import.fcpbundle` under the fixture's `fcp/` dir → FCP auto-selects the imported event → File > Export XML… → parse FCP's own re-serialization. Import is confirmed on the filesystem (event folder inside the bundle), never by trusting the UI. The QA library is closed afterwards; other libraries are never touched. | everything Resolve checks **plus mute** (re-export preserves `adjust-volume -96dB`) | — |
| Premiere | Launch-time ExtendScript: Premiere only executes scripts at startup (`<binary> /C es.processFile <jsx>`), so the runner launches its own instance with a generated script that builds a scratch project, imports the FCP7 XML, walks the sequence, writes tick-exact JSON, closes the project unsaved; the runner then force-quits that instance. Aborts if Premiere is already running. | fps, resolution, total length, per-clip record/source frame ranges, media paths, stills | mute (levels live in an audio filter ExtendScript doesn't read) |

Prerequisites:

- All three editors installed (missing ones are reported SKIP).
- **Accessibility permission** for the process running the scripts (the
  Resolve menu click and all FCP driving go through System Events). If a leg
  aborts on a menu click, grant the terminal/agent in System Settings >
  Privacy & Security > Accessibility.
- **Premiere must be closed** before its leg (the runner refuses to kill a
  running instance — it can't know what's unsaved).
- FCP and Resolve may be open or closed; the runners launch them if needed.
  Expect apps to steal focus while the suite runs — don't type over it.

## Tier 2 — visual verification (agent eyes or human eyes)

The structural tier proves the editors *agree with us about the metadata*.
The visual tier proves the right pixels/waveforms are actually on the
timeline — this is what catches "metadata consistent but wrong media" bugs,
and it's the only way to check mute where the API hides it.

Open the imported timeline in the editor (after a Tier 1 run: Resolve's
`buttercut-qa-*` project, FCP's `buttercut-qa-import` library, or re-run the
Premiere import by hand) and check it against
`libraries/qa-editor-roundtrip/expected_visuals.md`, which maps every timeline
second to what must be on screen: background color, giant clip letter, the
burned-in `SRC hh:mm:ss.f F<frame>` ticker (must match the source trim
frame-accurately), and the waveform pattern (one beep/s = A, double = B,
long = C; the muted clip shows **no** waveform level; the still is silent).

An agent with screenshot ability works through it position by position
(park the playhead at each row's start/middle/end, compare viewer + timeline
waveforms); a human can eyeball the whole thing in under a minute. This tier
costs tokens/attention — use it when Tier 1 passes but you're chasing a
content-level doubt, or as a pre-release once-over.

### Driving Tier 2 agent-side (recipes verified 2026-07-12)

The `integration-tests` skill (`skills/integration-tests/`) wraps both tiers —
it runs `run_all.rb` and then drives this visual pass using the recipes below,
which it carries as helper scripts (`resolve_park.rb`, `fcp_park.rb`,
`premiere_open_all.rb`, `mouse.js`). This section documents the underlying
technique.

A full agent pass (30 positions × 3 editors) has been run from an agent shell
with Accessibility + Screen Recording permission. What to check: each clip
row at `record_in`, a middle frame, and `record_out − 1` (`record_out` itself
already shows the *next* clip); at timeline frame `t` the ticker must read
`F(row_in + t − record_in)`. One full-window screenshot per scenario covers
the waveform column — and mute, invisible to Resolve's and Premiere's APIs,
IS visible on their timelines: the muted clip draws a flat audio waveform,
and a held still is a video clip with no audio beneath it. (FCP's mute is
already covered structurally by the re-export's `adjust-volume`.)

Parking the playhead, per editor:

- **Resolve (free edition):** same job-file pattern as the dump script — an
  in-app "park" Lua in the Fusion `Scripts/Utility/` folder reads a frame
  number, computes NDF timecode at the nominal integer rate from
  `GetStartFrame()`, calls `timeline:SetCurrentTimecode(tc)`, and writes a
  readback report; triggered by the same Workspace > Scripts menu click. The
  Scripts menu re-scans only when opened, so after installing a new script
  open the Workspace menu once and retry. NDF-at-nominal is exact here only
  because the QA timelines start at 0 and run under a minute; drop-frame
  timelines read back with `;` separators — compare digits only.
- **FCP:** reopen `fcp/buttercut-qa-import.fcpbundle` with `open`, then open
  the project by double-clicking its browser row — System Events' `click at`
  only sends an AXPress, so a real double-click needs a CGEvent with
  `kCGMouseEventClickState` set (JXA + ObjC bridge). Park with Cmd+2 (focus
  the timeline), ⌃P, typed `m ss ff` digits, Return. Free boundary
  confirmation: FCP's viewer draws corner "L" badges on a clip's first/last
  frame and sprocket-hole borders at media limits.
- **Premiere:** render a variant of the dump jsx that imports *every*
  scenario XML into one scratch project, opens each sequence
  (`app.project.openSequence`), saves, and does **not** close — all scenarios
  become timeline tabs in a single launch, and quitting afterwards is
  dialog-free because the project was saved. Park by clicking the Program
  monitor's timecode field, typing digits, Enter.

Screenshots: `screencapture -x -R x,y,w,h` takes points (image px ÷ 2 on a
2× retina display); crop tight to the viewer so the ticker is legible.

Both Tier-1 legs keep only the last imported scenario (scratch
projects/libraries are deleted on each run), so for Resolve and FCP work
scenario-by-scenario: re-run that scenario's Tier-1 leg to import it, then
walk its positions.

## Edition notes (core vs Pro)

The suite and fixture are identical in both editions — keep them byte-identical
(see "minimize Pro divergence"; edit in core, pull into Pro). Today Pro's
export output for a single-track cut must match core's, so both editions run
the same checks. When Pro-only export features ship (multi-timeline etc.), add
Pro-only cut fixtures + expected files here behind an
`if ButterCut.pro?` branch in the generator — the comparator and per-editor
plumbing already handle multiple tracks on the dump side (Resolve/Premiere
dumps include every track).

## Troubleshooting

- **Resolve: "No report … check Resolve's console"** — open Workspace >
  Console inside Resolve; the Lua script prints its failure there. Usually the
  job file is stale or the XML path moved.
- **Resolve: menu item missing** — the Scripts menu re-scans on open; if
  "ButterCut QA Dump" isn't listed, the auto-install failed (check
  `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/`).
- **Resolve: `source_out` mismatch on media with embedded timecode** —
  Resolve's `GetSourceStartFrame`/`GetSourceEndFrame` convert through the
  media's embedded start timecode, and each endpoint independently picks up a
  ±1 rounding (observed on qa_filmF: raw spans of 192 for a 192-frame clip
  but 121 for a 120-frame one). `verify_resolve.rb` absorbs that jitter by
  deriving the out-point from `left_offset` + the record span, so a
  comparator failure here means the raw span disagreed by *more* than ±1 —
  a real retime/conform problem, not the rounding. Confirm visually (Tier 2)
  before blaming the export.
- **FCP: aborts at "Open Library" dialog** — FCP's import dialog changed, or
  a modal (update prompt, etc.) was in the way. Run once by hand to see what's
  on screen; the runner's AppleScript lives inline in `verify_fcp.rb`.
- **FCP: "Expected sidebar selection …"** — FCP stopped auto-selecting the
  imported event. Select the event named after the fixture's first clip
  (`qa_clipB`) manually and re-run, then fix the runner.
- **Premiere: no report after 5 minutes** — either a first-run dialog blocked
  startup (launch Premiere once by hand, dismiss everything, quit) or the
  launch-script flag is gone. `/C es.processFile` rides ExtendScript, which
  Adobe supports **through ~September 2026**; after that this leg must move to
  a UXP panel (no unattended loader exists yet: panels load via the UXP
  Developer Tool GUI + Settings > Plugins > "Enable developer mode"). The
  Premiere DOM equivalents are documented — `Project.createProject`,
  `project.importFiles`, `VideoTrack.getTrackItems`, `fs.writeFile` — so the
  jsx translates nearly 1:1 when the time comes.
- **Anything driving keystrokes lands in the wrong place** — something stole
  focus mid-run (notification, user typing). Re-run the leg; the runners are
  idempotent.

## Extending the fixture

The full matrix design (11 scenarios: PAL 25, 59.94, every supported
container, geometry/rotation, audio edges, mixed-rate conform, VFR) lives in
`tmp/plans/Expand-editor-roundtrip-test-matrix-2026-07-09.md`. To add a
scenario: add its name + tier to `QaHarness::SCENARIOS`, its definition to the
generator's `SCENARIOS` table (and any new media to `MEDIA_SPECS`) — the
run_all loop, verifiers, and comparator need no changes for same-rate cuts.

Worthwhile near-term additions:

- a **non-ASCII filename** (`Titel Kärte.png`-style) to exercise the
  percent-encoding path — one unescaped character imports as offline media,
- **captions**, if exports ever embed the cut's `dialogue` text — that would
  also give Tier 2 a text-vs-burned-in-frame cross-check,
- a **render-and-retranscribe** deep tier: render the imported timeline out of
  the editor, then ffprobe/whisper the render and assert the beep pattern /
  spoken content order — proves final pixels+audio without anyone watching.

## File map

```
qa/
  editor-roundtrip.md                     ← this runbook
  scripts/
    generate_qa_fixture.rb                ← fixture library + cut + expected files
    run_all.rb                            ← fixture → exports → all verifiers
    qa_helpers.rb                         ← shared paths, editor registry, leg plumbing
    compare_timeline.rb                   ← shared comparator (exact frames)
    verify_resolve.rb                     ← Resolve leg (drives the in-app script)
    resolve/ButterCut QA Dump.lua         ← runs inside Resolve, dumps timeline JSON
    verify_fcp.rb                         ← FCP leg (System Events + re-export parse)
    verify_premiere.rb                    ← Premiere leg (launch-time ExtendScript)
    premiere/buttercut_qa_dump.jsx.template ← runs inside Premiere at launch
libraries/qa-editor-roundtrip/            ← generated fixture (gitignored)
  media/ …                                ← synthetic self-identifying footage
  cuts/<scenario>.yaml + exports (<scenario>_<editor>.xml/.fcpxml) + qa-actual_*.json
  expected_<scenario>.json                ← ground truth (frames)
  expected_visuals.md                     ← ground truth (eyes), all scenarios
  fcp/ …                                  ← FCP QA library bundle + re-exports
```
