# Creating a Video Library

A **library** organizes your video footage along with the transcripts, contact sheets, and summaries Claude needs to edit it. Creating one is the first thing you do with ButterCut — you can't build a cut until a library is processed.

Just tell Claude you want a new library and it walks you through setup:

```plaintext
You: "I want to build a new library"

Claude: [Guides you through library setup and asks for details]

You:
  - Library name: "wedding"
  - Video location: "/path/to/videos"
  - Language: "English"

Claude: [Automatically processes all videos]
  ✓ Creates the library structure
  ✓ Transcribes audio with word-level timing (WhisperX)
  ✓ Builds a contact sheet for every clip
  ✓ Writes a short summary of each clip

Result: Full footage analysis, ready to build a cut
```

Claude handles parallel processing, metadata extraction (via FFmpeg), and analysis. Each library is self-contained under `libraries/[library-name]/`, with `library.yaml` as its source of truth.

## Adding footage or resuming

The same flow handles three cases:

- **New project** — creates the library, gathers project info, runs analysis end to end.
- **Resume** — reopens an existing library and continues from wherever analysis left off.
- **Add footage** — appends new clips and analyzes just those.

Just point Claude at the library or the new files and say what you want.

## Walkthrough

See the [full walkthrough](example-library-setup.md) for a detailed example of setting up a library from wedding footage.
