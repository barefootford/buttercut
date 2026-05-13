# Pipeline failure notes — analyze-video memory blow-up

**Started:** 2026-05-11
**Context:** Two consecutive kernel panics during full-pipeline benchmark on `programmer-story-benchmark` (93 clips). Both crashed during wave 1 of `analyze-video`. Panic message indicated swap exhaustion ("100% of segments limit (BAD) with 29 swapfiles and LOW swap space") rather than any software bug.

## Hypothesis

The new grid-montage analyze flow has a much larger per-sub-agent working set than the old per-frame flow used in runs 1–4. With 4 parallel sub-agents on a 16 GB Mac, peak memory is exhausting RAM + swap.

Suspect contributors per sub-agent:
1. `ffmpeg` decoding the source DJI .mov to extract grid frames (decode buffers can be hundreds of MB per process for high-bitrate files)
2. ImageMagick / mini_magick assembling the grid JPG (can hold the full uncompressed grid in memory)
3. Claude Code sub-agent process itself reading the multi-MB grid JPG into context (one per clip, more for long clips with multiple grids)
4. Multiple of the above in flight when the agent processes its 10-clip batch sequentially (ideally only one clip's resources in flight at a time, but cleanup may lag)

## Plan

1. Measure baseline memory with the system idle (no benchmark running).
2. Start a continuous memory sampler in the background, writing to disk so the data survives a crash.
3. Run **one** analyze sub-agent on a small batch (e.g. 3 short clips first, then maybe 3 long clips) and watch peak memory.
4. Also instrument `grid_montage.rb` directly (without an agent) to isolate the ffmpeg + ImageMagick footprint from the agent's footprint.

## Sampler approach

Append-only `tee` of `vm_stat`, `top -l 1 -o mem -n 10`, and `ps` snapshots every 5s into `tmp/memlog.txt`. Don't read the log into context — only `tail` it after a phase ends so we can summarize.

---

## Run 0 — baseline (idle)

**Hardware:** 16 GB physical (`hw.memsize = 17179869184`). 16 KB page size.

**Idle state (just after the crash + reboot):**
- Active pages: 450116 → ~7.0 GB
- Inactive: 441244 → ~6.7 GB
- Wired: 84834 → ~1.3 GB
- Free: 15384 → ~241 MB
- Pages stored in compressor: 1145 (5 MB)
- **Swap: 0.00 MB used, 0.00 MB total** (no swapfiles created since reboot — clean slate)

So baseline working set is ~8.3 GB (active + wired). About 7 GB of headroom on disk pages that could be evicted.

---

## Background memory sampler

Sampler script: writes `vm_stat | head -20` plus `ps -axo pid,rss,command | sort -k2 -n -r | head -15` plus `vm.swapusage` every 5 seconds, appending to `/tmp/memlog.txt`. Append-only, survives crash. Sampler PID logged with the experiment.

---

## Run 1 — single `grid_montage.rb` on a 280s clip (NO sub-agent)

**Goal:** isolate ffmpeg + ImageMagick footprint from the agent's footprint. Run grid_montage directly with `/usr/bin/time -l` to capture peak RSS.

**Command:**
```
/usr/bin/time -l ruby skills/analyze-video/grid_montage.rb \
  ".../DJI_20250423212229_0253_D.mov" /tmp/grid_test/grid.jpg
```

Clip: 280s, single grid (≤10 min so one chunk → one ffmpeg call).

**Result:**
- Wall: **6.83 s** (3.84 user, 2.06 sys)
- **Maximum resident set size: 4,805,115,904 bytes ≈ 4.8 GB** (includes children — i.e. the ffmpeg child process)
- Ruby's own peak memory footprint: 9.3 MB (negligible)
- Output: 164 KB grid.jpg
- 47,149 involuntary context switches → kernel was actively preempting

**This is the smoking gun.** A single grid_montage call on one ~5-min clip peaks at **~4.8 GB RSS** in its ffmpeg child. With wave 1 of analyze running 4 parallel sub-agents, **peak across the wave = 4 × ~4.8 GB ≈ 19 GB** just for ffmpeg, on a 16 GB Mac. Add the four sub-agent JS processes, the parent agent, the Claude Code parent, and the 8 GB baseline working set, and we swap-exhaust within seconds. That matches the panic ("100% of segments limit, LOW swap space").

### Why so much?

Look at how `grid_montage.rb` calls ffmpeg:

```ruby
def build_command(filter_path, output, seek_times)
  inputs = []
  seek_times.each do |t|
    inputs.concat(["-hwaccel", "videotoolbox", "-ss", t.to_s, "-i", @video_path])
  end
  ...
end
```

For a 4×4 grid that's **16 inputs of the same source file**, each opened as a separate `AVFormatContext` + `AVCodecContext`, with `-hwaccel videotoolbox` allocating a VideoToolbox decoder session per input. On Apple Silicon the GPU memory is unified, so VT decoder sessions count against process RAM. 16 hardware decoder sessions on a high-bitrate HEVC source = multi-GB resident.

The `-ss` before `-i` is a fast input-level seek, but each input still has to open the container, probe streams, and hold state.

### Hypotheses to test next

1. **Single ffmpeg with `select+tile` filter** instead of 16 inputs — should drop to ~1 decoder context.
2. **Drop `-hwaccel videotoolbox`** — software decode may use less RAM (no VT session bookkeeping) at the cost of CPU time.
3. **Smaller grid** (3×3 = 9 inputs instead of 16) as a stopgap.
4. Confirm that the pre-grid-flow analyze (per-frame extraction, runs 1–4) doesn't show this footprint.

---

## Run 2 — variant comparison (same 280s clip, no agent)

All variants build the same 4×4 (or 3×3) grid from the same source clip on an idle system. Memory is `maximum resident set size` from `/usr/bin/time -l` (includes child processes — i.e. ffmpeg).

| Variant | Inputs to ffmpeg | hwaccel | Peak RSS | Wall | Verdict |
|---|---|---|---|---|---|
| `hwaccel` (current default) | 16 (one per tile) | videotoolbox | **4.8 GB** | 6.8 s | Fast but RAM-hungry — what we ship today |
| `software` | 16 | none | **8.4 GB** | 16.5 s | Worse on every axis. Hwaccel is helping memory, not hurting |
| `fewer_inputs` (3×3) | 9 | videotoolbox | **6.5 GB** | 2.2 s | Higher than 4×4 — likely just variance, but no win. Fewer tiles ≠ less RAM |
| `single_input` | 1 + `fps,tile` filter | n/a (decode all) | **0.7 GB** | **227 s** | **6.5× memory reduction**. 33× slowdown — fps filter walks the whole video sequentially |

### Key insight

The peak RSS does **not** scale linearly with number of inputs (3×3 was *higher* than 4×4 on one trial). That suggests the dominant cost isn't N independent decoder sessions — it's the **per-input VideoToolbox context setup overhead** combined with how ffmpeg handles many parallel input contexts. There's a fixed-cost-per-input that's huge on Apple Silicon's unified memory.

### Tradeoff

The current `-ss before -i` × N approach is **fast but memory-pathological** because each `-i` opens a new VideoToolbox decoder session and ffmpeg holds them all simultaneously. 

The single-input fps+tile approach is memory-safe but unusably slow — it would turn a 6 s grid build into 227 s × 93 clips ≈ 5.8 hours of analyze just for frame extraction.

There's a middle ground worth testing:
- **N independent ffmpeg invocations** (one per tile) writing tiles to disk, then a final composing pass. Each invocation only holds 1 decoder session, peak ≈ 1 × per-input cost, but they run sequentially so peak doesn't multiply. Slower than current but should be fast enough.
- **Fewer inputs grouped** (e.g. 4 batches of 4 inputs each, sequential) — same idea, fewer ffmpeg invocations.

### Updated picture of the crash

If a single grid_montage peaks at ~5 GB and 4 sub-agents run in parallel, instantaneous peak ≈ **20 GB ffmpeg RSS** alone. On a 16 GB Mac this is unrecoverable: macOS compresses, then swaps, then thrashes, then `watchdogd` can't check in within 92 s, then panic. That's exactly the message we got.

---

## Run 3 — sequential single-input ffmpeg + ImageMagick compose ✅

**The fix.** Instead of one ffmpeg call with N parallel inputs, run N **sequential** ffmpeg calls each with **one input** (extract one tile per call), then compose all N tiles with `magick montage`. Same source, same 4×4 grid, same labels.

Script: `/tmp/grid_sequential.rb`.

| Metric | Current (`grid_montage.rb`) | Sequential (proposed) | Change |
|---|---|---|---|
| Peak RSS | 4.8 GB | **566 MB** | **−88%** (8.5× lower) |
| Wall | 6.8 s | 8.2 s | +21% |
| Output | 164 KB | 540 KB | larger because magick montage uses higher quality |

Why it works: each ffmpeg invocation only opens **one** VideoToolbox decoder session, exits, and frees it. The sequential loop's instantaneous peak is the cost of one decode. Total wall time barely changes because each decode + seek is fast (~0.5 s) and the process startup overhead is small relative to that.

### Crash math with the fix

| Scenario | Per-agent peak | 4-parallel peak | Fit in 16 GB? |
|---|---|---|---|
| Today | ~5 GB | ~20 GB | No — swap exhaustion → panic |
| Sequential | ~0.6 GB | ~2.4 GB | Yes, with 12 GB headroom |

### Other knobs that don't matter

- Disabling hwaccel: makes memory worse (8.4 GB) AND slower (16 s). Don't touch.
- 3×3 grid: doesn't help memory (still 6.5 GB). The problem is per-input cost, not number of inputs as such.
- single-input fps+tile filter: drops memory the most (0.7 GB) but is 33× slower. Not viable.

---

## Recommendation

Two changes worth shipping:

1. **Rewrite `grid_montage.rb` to use the sequential single-input + montage compose pattern.** Keep the 4×4 grid, keep the timestamp labels, keep the chunked-by-10-min behavior. Just change the inner loop from "build one ffmpeg with 16 inputs" to "build 16 ffmpegs with 1 input each, then magick montage". Estimated peak per clip: ~600 MB instead of ~5 GB. Estimated wall time penalty: ~20%.

2. **Keep parallelism cap at 4 in `skills/analyze-video/SKILL.md`** once the fix lands. With 600 MB per agent the cap is comfortable. Without the fix, the cap should be 1 or 2 and the crash risk persists.

This will also make analyze faster on the wall in practice because the OS won't be swapping during the run.

### Things I did not test

- Long clips that produce multiple grids (>10 min). The pattern should hold but the per-grid peak is the same; the loop just runs more times.
- Whether `magick` (ImageMagick) is reliably installed — `grid_sequential.rb` falls back to `montage` (ImageMagick 6) if `magick` (ImageMagick 7) isn't on PATH. Worth confirming as part of `setup` skill.
- Whether `ffmpeg` could output directly to a final composed image without ImageMagick (e.g. concatenating tiles via shell + `xstack` from disk inputs in a final pass). Plausible but ImageMagick already works.

---

## Cleanup performed at end of experiment

- Stopped background memory sampler (PID logged in original turn).
- Stopped `caffeinate -dimsu` started during this experiment.
- Left `/tmp/memlog.txt`, `/tmp/grid_test/`, `/tmp/grid_compare.rb`, `/tmp/grid_sequential.rb` in place for inspection.
- Library state from the failed benchmark is unchanged (transcripts intact, partial visual+summary files from wave 1 still present).


