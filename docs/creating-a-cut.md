# Creating a Cut

Once your library is processed, Claude builds a cut through an interactive conversation and exports a timeline for your editor. A "cut" can be one of four shapes — Claude asks which one you want:

- **Scene** — one beat or moment, typically 30–60s.
- **Selects** — a flat reel of clips matching some criteria (best takes, mentions of a topic, B-roll on a theme). Length follows the footage.
- **Roughcut** — a story-shaped cut, usually 2–8 minutes, with full narrative planning.
- **Custom** — anything else you describe.

## Example

```plaintext
You: "Let's create a cut"

Claude: Library is ready (29/29 clips processed).
        What kind of cut do you want — scene, selects, roughcut, or custom?

You: "A roughcut of just the meetup coverage"

Claude: [Asks a few preference questions]
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

Claude: [Makes editorial decisions and builds the cut]
        ✓ Reviewed contact sheets, summaries, and transcripts
        ✓ Selected 29 clips (4:32 total)
        ✓ Exported to FCPXML

Result: Ready-to-import timeline at:
        libraries/[library]/cuts/[name]_[datetime].fcpxml
```

Claude makes editorial decisions based on the contact sheets, summaries, and transcript analysis plus your direction, then exports a timeline for your editor.

## Output

Every cut exports a timeline into `libraries/[library-name]/cuts/`:

- **Final Cut Pro X** → `.fcpxml`
- **Adobe Premiere Pro** → `.xml`
- **DaVinci Resolve** → `.xml`

If you've enabled it, Claude can also drop a copy on your Desktop and open the file directly in your editor after export.

## Direct XML generation

To generate a timeline in Ruby without going through Claude, see [basic-xml-generation.md](basic-xml-generation.md).
