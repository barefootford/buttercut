---
name: full-transcript
description: Exports all dialogue from every clip in a library into a single text file. One clip per block — filename, then its spoken words. Use when the user asks for a "full transcript", "full script", or wants all the dialogue from a library in one place.
---

# Skill: Full Transcript

Exports all spoken dialogue from a library's audio transcripts into a single `full_transcript.txt` file in the library root.

## Run

```bash
ruby lib/buttercut/full_transcript.rb <library-name>
```

## Output

`libraries/<library-name>/full_transcript.txt` — one block per clip:

```
filename.mov
Dialogue text from that clip.

filename2.mov
More dialogue from the next clip.
```

Clips with no audio transcript are skipped. Clips with a transcript but no spoken words show `[no dialogue]`.

## After running

Always share the output file path as a clickable link in your response so the user can open it directly.
