---
name: integration-tests
description: Run the full editor round-trip QA — Tier 1 (deterministic import/verify matrix via qa/scripts/run_all.rb) followed by the Tier-2 visual pass, driving Final Cut Pro, DaVinci Resolve, and Premiere and checking viewer screenshots against expected_visuals.md. Developer-only. Use when the developer asks to "run the integration tests", "run the roundtrip QA", "run the editor QA", "run tier 2", or "visually verify the exports".
---

# Skill: Editor round-trip QA (Tier 1 + Tier 2)

Runs both tiers of `qa/editor-roundtrip.md` end to end. Tier 1 is the
deterministic PASS/FAIL matrix; Tier 2 is the visual pass — you (the agent)
park each editor's playhead at known timeline positions, screenshot the
viewer, and check the burned-in ticker/colors/waveforms against
`libraries/qa-editor-roundtrip/expected_visuals.md`. Read that runbook first
if anything here is surprising; this skill only adds the driving recipes.

Prerequisites:

- Developer checkout (`.buttercut_mode` present) — never run in a video-editor session.
- Accessibility **and** Screen Recording permission for this agent's shell.
- **Premiere closed** before starting (both tiers launch their own instance).
- Editors steal focus while this runs — warn the developer not to type over it.

Ask the developer whether to run the fast tier or `--full` (default to `--full`
before merges — that's the merge-confidence gate).

## Step 1 — Tier 1 (deterministic)

```bash
ruby qa/scripts/run_all.rb --full     # or without --full for the fast tier
```

Report the PASS/FAIL matrix. If a leg fails, stop and investigate before
Tier 2 — the runbook's troubleshooting section covers the known aborts. A
Resolve `source_out` failure of more than ±1 is a real disagreement (the leg
already absorbs the ±1 embedded-timecode jitter documented in the runbook).

## Step 2 — Tier 2 (visual)

### What to check at each position

Open `libraries/qa-editor-roundtrip/expected_visuals.md`. For every clip row
of every scenario you're checking, park at three timeline frames — `record_in`
(first frame), a middle frame, and `record_out - 1` (last frame; `record_out`
itself already shows the *next* clip) — and verify in the viewer screenshot:

- **Background color + giant letter** match the row.
- **SRC ticker frame**: at timeline frame `t`, the ticker must read
  `F(row_in + (t - record_in))` — e.g. parking at the last frame of a clip
  trimmed `F360 → F480` must show `F479`. The ticker format is
  `<letter> SRC hh:mm:ss.ffffff F<n>`; compare the `F<n>` number, it's exact.
- The still (`qa_title_card.png` rows) shows the yellow TITLE CARD, no ticker.

Then one **full-window screenshot per scenario** showing the timeline itself:

- The muted clip's audio is drawn **flat** in Resolve and Premiere (mute is
  invisible to their APIs, so this screenshot is the only mute check there;
  FCP's mute is already verified structurally by Tier 1's re-export).
- Other clips show their beep pattern (1/s = one short, 2/s = double, long).
- The still appears as a video-only clip with **no audio** under it.

### Screenshots

`screencapture -x -R x,y,w,h out.png` takes coordinates in **points**. To find
them: take a full screenshot (`screencapture -x full.png`), Read it, locate
the viewer, then convert with `points = image_px × (screen_width_points /
image_width_px)` (Read's rendering is downscaled; on this 2×-retina display
the factor has been ≈0.8 for a 2000px rendering). Crop tight to the viewer so
the ticker text is legible; re-crop rather than squint.

### Per-editor driving

Both Tier-1 legs keep only the **last** scenario imported (each run deletes
the previous scratch project/library), so for Resolve and FCP work one
scenario at a time: re-run that scenario's Tier-1 leg to import it, then do
its visual positions. Premiere imports everything in one launch instead.

**DaVinci Resolve**

1. `ruby qa/scripts/verify_resolve.rb <export> <expected>` — imports the
   scenario into a fresh `buttercut-qa-*` project (skip for the scenario that
   is already current after Tier 1).
2. Make sure Resolve is on the Edit page (screenshot; Shift+4 switches to it).
3. Park: `ruby skills/integration-tests/resolve_park.rb <frame>` —
   prints a report with Resolve's own `tc_readback`; compare its digits only
   (drop-frame timelines read back with `;` where `:` was set). A digit
   mismatch is a failed park, not a failed export.
4. Screenshot the timeline viewer per position; full window for waveforms.

**Final Cut Pro**

1. `ruby qa/scripts/verify_fcp.rb <export> <expected>` — re-imports (it closes
   the QA library when done), then reopen it:
   `open libraries/qa-editor-roundtrip/fcp/buttercut-qa-import.fcpbundle`.
2. Open the imported project: find its row in the browser on a screenshot,
   then double-click it with
   `osascript -l JavaScript skills/integration-tests/mouse.js <x> <y> 2`
   (System Events `click at` is only an AXPress — it won't open the project).
3. Park: `ruby skills/integration-tests/fcp_park.rb <frame> <fps>`
   (fps from the scenario: 30, 29.97, or 23.976).
4. Bonus check: FCP draws corner "L" badges in the viewer on a clip's first
   and last frame, and sprocket-hole borders at media limits — free
   confirmation that a boundary park really is the boundary.

**Premiere**

1. `ruby skills/integration-tests/premiere_open_all.rb` — launches
   Premiere once with every scenario imported into one saved scratch project,
   all sequences as timeline tabs, and **leaves it running**.
2. Select a scenario's tab (single `mouse.js` click on the tab), then park by
   clicking the Program monitor's timecode field (`mouse.js`), typing the
   digits and Return:
   `osascript -e 'tell application "System Events" to tell process "Adobe Premiere Pro" to keystroke "<digits>" & return'`
   Digits are NDF `m ss ff` at the nominal rate, same convention as
   `fcp_park.rb` prints (e.g. frame 315 @ 30 fps → `1015`).
3. Screenshot per position; full window for waveforms.
4. Quit when done — dialog-free because the project was saved:
   `osascript -e 'tell application id "com.adobe.PremierePro" to quit'`.

## Step 3 — Report

Give the developer one summary: the Tier-1 matrix verbatim, then a Tier-2 table —
scenario × editor × position, each with the expected vs observed ticker frame
and the waveform/mute verdict — and a clear overall PASS/FAIL. Keep
screenshots in the session scratchpad; nothing from this skill belongs in the
repo or the fixture library.

## Known quirks

- Parking timecode math everywhere in this skill is NDF at the nominal
  integer rate — valid because the QA timelines start at 0 and are under a
  minute. Don't reuse the parkers on long drop-frame timelines.
- If a keystroke lands in the wrong app, something stole focus mid-run;
  re-run that position (every step here is idempotent).
- If the Workspace > Scripts menu is missing "ButterCut QA Park", open the
  menu once by hand (it re-scans) — the driver installs the script
  automatically.
- To uninstall the in-app park script:
  `rm "~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/ButterCut QA Park.lua"`.
