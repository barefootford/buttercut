# Transcript refinement instructions

Companion file for `SKILL.md`. Invoked from SKILL.md Step 4 when the parent passed `transcript_refinement: true`. Reviews a WhisperX transcript and corrects misheard words using the context strings the parent supplied, in place.

## Step 1 — Gather inputs from the parent

The parent has already supplied these inline in your prompt:

- `transcript_path` — absolute path to the prepared transcript JSON
- `user_context` — string, may be empty
- `footage_summary` — string, may be empty

Do NOT open `library.yaml` or search the filesystem for additional context — if the parent didn't pass it, treat it as unavailable. If the parent invoked refinement with only empty context strings, proceed anyway. Catch issues from just what the parent gave you and the transcript.

## Step 2 — Extract a compact script view

Run the shared extractor to produce a plain-text view of the transcript (one segment per paragraph, no timing metadata). Pick a sibling `.txt` path next to the transcript and pass it explicitly:

```bash
ruby .claude/scripts/script_extractor.rb <transcript_path> <transcript_path_with_.txt_extension>
```

Read ONLY that `.txt` file for the analysis steps below. Do NOT `Read` the full transcript JSON yet — it's large and you don't need its word-level structure to identify corrections.

## Step 3 — HARD RULE: preserve word count, never change timing

WhisperX produces word-level timing. The `segments[].words[]` array is 1:1 with the space-separated tokens in `segments[].text`. Splitting or merging tokens breaks this alignment and corrupts downstream timing used by roughcut.

Allowed:
- **1→1 token spelling fix** (same count, different characters). Transcript: `"The bike ended up in a second-floor apartment over near the Tenderlohn, which is where the cops met us."` Fix: `Tenderlohn` → `Tenderloin` — one mangled token replaced by the correct San Francisco neighborhood spelling, same single-token slot. Surrounding words are untouched.
- **N→N token phrase fix** (same count across a phrase). Transcript: `"We had been planning to ride out to Walnut Creak for the weekend before the whole thing happened."` Fix: `Walnut Creak` → `Walnut Creek` — two tokens stay two tokens; only one character-set changes, but the phrase is treated as the unit of edit for safety.

Disallowed:
- **1→2 token split**. Transcript: `"Her cousin grew up in Sanjose and still lives in the same house her parents bought in the sixties."` The correct spelling is "San Jose" (two tokens), but WhisperX fused it into a single token covering the speaker's fast delivery. Splitting that one timing slot into two requires guessing where "San" ends and "Jose" begins — don't do it. (See squashing technique below for the right move.)
- **2→1 token merge**. Transcript: `"We walked every single block of the neighborhood looking for the stolen bike that afternoon."` If you wanted to "normalize" `every single` into a single `everysingle` token, you'd drop one entry from the words array. Same corruption in reverse. Don't.

Never modify timing fields (`start`, `end`, `duration`, `word.start`, `word.end`) for any reason.

**Squashing technique**: when the correct term is naturally multi-word but the transcript has it as a single nonsense token, squash the correction into a single-token form to preserve word count. Downstream agents (analyze-video, roughcut) care about accurate word recognition, not cosmetic spacing — prefer squashing over skipping.

- Transcript: `"Her cousin grew up in Sanjose and still lives in the same house her parents bought in the sixties."` Fix: `Sanjose` → `SanJose` (squashed single-token form). Downstream agents will still recognize the city. NOT `San Jose` — that's a disallowed 1→2 split.
- Transcript: `"Our rental was a tiny cottage right on the edge of Tenderknob, close to a Burmese place we ended up at every single night."` The speaker meant "Tendernob" (the informal Tenderloin/Nob Hill border). Fix: `Tenderknob` → `Tendernob` (1→1 spelling fix, stays one token).
- Transcript: `"She went to a little Catholic school in the Mission called Saintvincent when she was a kid, and her sister went there too."` Fix: `Saintvincent` → `SaintVincent` (squashed; preserves the one-token slot).

If even squashing won't work (genuinely requires splitting or merging tokens), do NOT edit. Note it in your return summary instead. Example: `"Skipped: 'everysingle' in segment 12 should likely be 'every single' (two words), but a 1→2 split would corrupt timing."`

## Step 4 — Identify corrections from the compact script

Scan the `.txt` view against the confidence rubric. Every candidate must also satisfy Step 3's word-count rule.

- **Context-named term match**: correct if the intended term appears in `user_context` or `footage_summary` and the transcript has a close mishearing. Example: `footage_summary` says "the couple got married at a small vineyard in Sonoma over Labor Day weekend." The transcript has `"We drove all the way up to Sanoma on Friday afternoon and the traffic was unbelievable."` "Sanoma" is a 1→1 mishearing of the context-named location — fix it.
- **Nonsense-token match**: correct if the transcript token is a non-word nonsense string with a clear real-world spelling implied by context. Example: transcript says `"His mother grew up in Pleasantton and worked at the little cafe downtown for twenty years."` "Pleasantton" isn't a real place — but "Pleasanton" is a real East Bay city and nothing else is phonetically close. 1→1 spelling fix.
- **Self-witness rule**: correct if the proposed correct form appears elsewhere in the SAME transcript AND the suspect token is phonetically close. Example: an early segment says `"Andrew and Gordon ended up getting dinner at a Thai place in Pacific Heights that night after everything calmed down."` A later segment says `"Pacific Heights has been Andrew's favorite neighborhood since he first moved to the city back in 2015."` If a third segment has `"We drove through Pasific Hites on the way to the station."`, fix it — the correct form is witnessed twice elsewhere in the same transcript.
- **Do NOT correct based on general world knowledge alone**. Example: transcript says `"Andrew dropped by a little market on Fillmore for snacks before we started the ride."` Even if you happen to know of a specific famous store on Fillmore, don't invent it — the generic phrasing might be exactly what was said. Require either a context naming or a self-witness. If neither exists, leave it.

Collect every authorized correction as an `old → new` pair before moving to Step 5.

## Step 5 — Apply each correction to the full JSON

Now (and only now) you need to touch the transcript JSON. For each correction, you must update three places so they stay consistent:

1. `segments[].text` — the sentence-level text
2. `segments[].words[].word` — the word-level array inside the owning segment
3. `word_segments[].word` — the top-level flat word array

Read the JSON targeted, not whole — use `Grep` to locate each occurrence and its surrounding lines, then `Edit` with a unique anchor.

### 5a — Update `segments[].text` with phrase context

Every correction must include at least one adjacent word of surrounding context. Never `Edit` on a bare word — even nonsense tokens — because Edit does substring matching, not word-boundary matching. Bare-word replacements silently corrupt legitimate substrings. For example, if you try to fix a misheard `"car"` by running `Edit replace_all=true old="car" new="far"`, you'll also rewrite every occurrence of `"carrot"` into `"farrot"`, every `"scared"` into `"sfared"`, and so on across the whole transcript. Always anchor the edit with at least one adjacent word.

Correct form:

- `Edit replace_all=true old="second-floor apartment over near the Tenderlohn" new="second-floor apartment over near the Tenderloin"` — 1→1 spelling fix in generous phrase context.
- `Edit replace_all=true old="ride out to Walnut Creak for the weekend" new="ride out to Walnut Creek for the weekend"` — 2→2 phrase fix.
- `Edit replace_all=true old="cousin grew up in Sanjose and still lives" new="cousin grew up in SanJose and still lives"` — squashed 1→1 fix.

**Case rule**: preserve the transcript's existing case. The goal is accurate word recognition for downstream agents, not proper-noun capitalization. If the transcript has "tundraloin" (lowercase), replace with "tenderloin" (lowercase) — don't upgrade to "Tenderloin". If the transcript has "Tundraloin" at a sentence start, replace with "Tenderloin" there. Match case-for-case; don't normalize. Exception: the squashing technique (Step 3) may introduce an internal capital to mark a word boundary (e.g. `Sanjose` → `SanJose`); the first letter's case still follows this rule.

### 5b — Update the two word-level arrays, anchored by `start`

Both `segments[].words[].word` and top-level `word_segments[].word` have their own entry for each token. These arrays aren't consumed downstream yet, but they're how we'll cut a single word or phrase out of a segment later, so keeping them consistent with the corrected `segments[].text` is load-bearing — don't leave them stale.

Anchor each word-array edit on the adjacent `start` timestamp so it's unique (the token alone may appear in many slots). Only the `word` field changes; timing fields (`start`, `end`, `score`, etc.) must stay untouched.

The transcript JSON is pretty-printed (`JSON.pretty_generate`), so each key sits on its own line. `Edit` does literal substring matching — your `old_string` must include the newline and indentation between `"word": "..."` and `"start": ...`. Use the exact whitespace from the file (open it with `Read` or `Grep -A` first to copy the indentation verbatim).

- Two-line anchor form (copy the real indentation from the file):
  ```
  Edit old='"word": "Sanjose",
              "start": 10.534' new='"word": "SanJose",
              "start": 10.534'
  ```
  Updates one entry; repeat for the other array.
- For an N→N phrase fix, update each token's word entry the same way, anchored by its own `start`.
- For the squashing case (e.g. `Sanjose` → `SanJose`), the word count is unchanged, so there's still exactly one word entry to update per array.

## Step 6 — Clean up the extracted script file

Delete the `.txt` file created in Step 2. It's scaffolding, not a deliverable.

```bash
rm <transcript_path with .json replaced by .txt>
```

## Step 7 — Return summary to the parent

Append a refinement line to your SKILL.md Step 5 response. Format:

- If corrections made: list them as `old → new` pairs, one per line.
- If no corrections needed: `"Refinement: no corrections needed"`.
- If some candidates were skipped for word-count reasons: `"Refinement: skipped N corrections that would have changed word count"` followed by the list.

The parent writes only `transcript: <filename>.json` to library.yaml — no new field needed.
