# ButterCut

**Make Claude your Video Editor**

Give Claude Code your video footage. Claude analyzes it, then builds roughcuts and sequences for Final Cut, Premiere, and Resolve.

Behind the scenes Claude uses ButterCut Skills and a nifty Ruby library to generate timelines for your editor.

## Watch the Demo

[![Watch ButterCut Demo on YouTube](https://img.youtube.com/vi/C3oMpyo8huQ/0.jpg)](https://www.youtube.com/watch?v=C3oMpyo8huQ)

*Click to watch the ButterCut demo on YouTube*

## Getting Started

1. **Clone or download ButterCut**
2. **Open Claude Code** in the ButterCut directory
3. **Tell Claude: "Install ButterCut"**

Claude will check your system and install any missing dependencies (Ruby, Python, FFmpeg, WhisperX).

For manual installation, see [docs/installation.md](docs/installation.md).

## Usage

First tell Claude to create a **Library**. A library encompasses (links to) video footage and audio and visual transcripts. Then tell Claude you want to create a **rough cut** or **sequence**.

### Creating a Video Library

```plaintext
You: "I want to build a new library"

Claude: [Guides you through library setup and asks for details]

You:
  - Library name: "wedding"
  - Video location: "/path/to/videos"
  - Language: "English"

Claude: [Automatically processes all videos]
  ✓ Creates library structure
  ✓ Transcribes audio with WhisperX
  ✓ Analyzes video frames
  ✓ Generates visual transcripts

Result: Full footage analysis ready for rough cut creation
```

Claude handles the parallel processing, metadata extraction, and transcript generation. See the [full walkthrough](docs/example-library-setup.md) for a detailed example of me setting up a library from my wedding footage.

### Creating a Roughcut or Sequence

Once your library is analyzed, Claude can create rough cuts through an interactive conversation:

```plaintext
You: "Let's create a new roughcut"

Claude: [Loads roughcut skill and analyzes footage]
        What should this roughcut focus on?
        - Full story
        - Just the meetup coverage
        - Short teaser sequence

You: "Just the meetup coverage"

Claude: [Asks 3 preference questions]
        - Narrative structure? (chronological, thematic, hook-based)
        - Target duration? (1-2 min, 3-5 min, 6-10 min)
        - Pacing style? (fast & punchy, conversational, cinematic)

You: "Start with presentations (5 sec clips), then interviews,
      then my closing reflection. 3-5 minutes, conversational pacing."

Claude: [Asks which video editor you want to use]
        - Final Cut Pro X
        - Adobe Premiere Pro
        - DaVinci Resolve

You: "Final Cut Pro X"

Claude: [Creates roughcut with editorial decisions]
        ✓ Combined visual transcripts
        ✓ Selected 29 clips (4:32 total)
        ✓ Exported to FCPXML

Result: Ready-to-import timeline at:
        libraries/[library]/roughcuts/[name]_[datetime].fcpxml
```

Claude makes editorial decisions based on transcript analysis and your preferences, creating a structured YAML roughcut. The roughcut is then exported for your editor using the Ruby library.

### XML Generation

For direct XML generation without Claude Code, see [docs/basic-xml-generation.md](docs/basic-xml-generation.md).

## Thanks

ButterCut was inspired by ambitious open source work from [Chris Hocking](https://github.com/CommandPost/CommandPost) and [Andrew Arrow](https://github.com/andrewarrow/cutlass/tree/main).

## License

MIT

## Contributing

Bug reports and pull requests welcome.
