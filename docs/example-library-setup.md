# Example: Setting Up a Wedding Video Library

This walkthrough shows a complete example of using ButterCut with Claude Code to analyze wedding footage. The entire process—from initial request to fully analyzed footage—happens in one conversation with automatic parallel processing.

---

## The Conversation

### **User**
> I want to build a new library

### **Claude**
I'll help you create a new library. Let me gather some information about your project:

**Questions:**
1. What would you like to name this library?
2. Where are your video files located?
3. What language is spoken in these videos?

### **User**
> wedding

### **Claude**
Perfect! The library will be named "wedding".

Now, what is the directory path containing your video files?

### **User**
> /Users/andrew/Final Cuts/Wedding Camcorder Footage

> [interrupts] Let's just grab the 10 smallest clips from inside that folder to start

### **Claude**
Got it! Let me find the 10 smallest video clips from that folder.

```
Finding videos... Found 20 videos total

10 smallest clips (184MB total):
  MVI_0307.MP4  (3.4MB)   - 2 seconds
  MVI_0316.MP4  (9.4MB)   - 5 seconds
  MVI_0311.MP4  (15MB)    - 8 seconds
  MVI_0322.MP4  (15MB)    - 7 seconds
  MVI_0326.MP4  (18MB)    - 9 seconds
  MVI_0304.MP4  (19MB)    - 9 seconds
  MVI_0306.MP4  (24MB)    - 12 seconds
  MVI_0308.MP4  (26MB)    - 13 seconds
  MVI_0302.MP4  (27MB)    - 13 seconds
  MVI_0313.MP4  (28MB)    - 14 seconds
```

Perfect! Setting up the library and starting footage analysis...

---

## What Happens Next (Automatically)

### Step 1: Library Setup
```
✓ Created libraries/wedding/
✓ Created libraries/wedding/transcripts/
✓ Created libraries/wedding/roughcuts/
✓ Created library.yaml with metadata for all 10 videos
```

### Step 2: Audio Transcription (Parallel Processing)
Claude launches 4 parallel agents, each handling one video:

```
Agent 1: Transcribing MVI_0307.MP4...
Agent 2: Transcribing MVI_0316.MP4...
Agent 3: Transcribing MVI_0311.MP4...
Agent 4: Transcribing MVI_0322.MP4...
[...8 agents running simultaneously]

✓ MVI_0307.json - Audio: (silence)
✓ MVI_0316.json - Audio: "They said, you want this and this? Yes."
✓ MVI_0311.json - Audio: (conversation about venue)
✓ MVI_0322.json - Audio: "Did he was gonna do that? Yep, he sure did..."
✓ MVI_0326.json - Audio: (champagne toast conversation)
✓ MVI_0304.json - Audio: (guest conversation)
✓ MVI_0306.json - Audio: "Are you kidding me?"
✓ MVI_0308.json - Audio: (dinner table conversation)
✓ MVI_0302.json - Audio: "I don't know who Jared is..."
✓ MVI_0313.json - Audio: "It's snowing!"

All audio transcription complete (word-level timing preserved)
```

### Step 3: Visual Analysis (Parallel Processing)
Claude launches 10 more parallel agents to analyze frames:

```
Agent 1: Analyzing frames for MVI_0307.MP4...
Agent 2: Analyzing frames for MVI_0316.MP4...
[...extracting frames with ffmpeg]
[...analyzing visual content with Claude]

✓ visual_MVI_0307.json - Wedding venue entrance, fairy lights
✓ visual_MVI_0316.json - Decorated storefront with blue lighting
✓ visual_MVI_0311.json - Outdoor pavilion with string lights
✓ visual_MVI_0322.json - Night venue exterior, gold garland
✓ visual_MVI_0326.json - Champagne glasses on pink table
✓ visual_MVI_0304.json - Reception area with guests
✓ visual_MVI_0306.json - Evening reception under light canopy
✓ visual_MVI_0308.json - Formal dinner table, gold plates
✓ visual_MVI_0302.json - Guest conversation area
✓ visual_MVI_0313.json - First-person walking in snow

All visual analysis complete
```

### Step 4: Summary Generated

**Claude automatically updates `library.yaml` with:**

```yaml
footage_summary: "Wedding reception footage shot on camcorder at night.
  The venue features an outdoor pavilion with elegant string light canopies
  overhead creating a magical evening ambiance. Footage includes formal
  dining tables with gold charger plates, white napkins, burgundy
  tablecloths, candlesticks, and floral centerpieces. The decorated venue
  entrance shows white fairy lights, gold garland, and blue accent lighting
  on the storefront. Captures casual conversational moments between guests,
  including a champagne toast scene with bottles and glasses on a pink
  table. One clip shows snowy outdoor conditions with first-person
  perspective of walking in the snow. Overall atmosphere is intimate,
  formal, and celebratory. Duration: 1 minute 32 seconds across 10 short
  clips."
```

---

## Final Result

### **Claude**
Library setup complete! I've successfully processed all 10 wedding video clips:

**Analysis Complete:**
- **Total footage:** 1 minute 32 seconds (183MB)
- **Audio transcription:** All 10 videos transcribed with word-level timing
- **Visual analysis:** All 10 videos analyzed with frame descriptions

**Footage Summary:**
This is wedding reception footage shot on camcorder at night. The venue features an elegant outdoor pavilion with string light canopies, formal dining tables with gold charger plates and burgundy tablecloths, and a decorated storefront entrance with fairy lights and gold garland. Footage captures casual conversations between guests, a champagne toast scene, and even includes one clip of snowy outdoor conditions. The overall atmosphere is intimate, formal, and celebratory.

**What's next?**
Now that all footage is analyzed, you can create a rough cut by using the `roughcut` skill. The rough cut generator will use the visual transcripts and audio transcripts to create a Final Cut Pro XML file based on your editorial direction.

All files are saved in:
- Library: `/Users/andrew/code/buttercut/libraries/wedding/library.yaml`
- Transcripts: `/Users/andrew/code/buttercut/libraries/wedding/transcripts/`

---

## File Structure Created

```
libraries/wedding/
├── library.yaml                          # Source of truth for library
├── transcripts/
│   ├── MVI_0307.json                    # Audio transcript
│   ├── visual_MVI_0307.json             # Visual transcript
│   ├── MVI_0316.json
│   ├── visual_MVI_0316.json
│   └── [...18 more transcript files]
└── roughcuts/                            # Ready for rough cut creation
```

---

## Key Features Demonstrated

1. **Automatic Discovery** - Claude found and sorted videos by size
2. **Parallel Processing** - 10 videos processed simultaneously (4 at a time)
3. **WhisperX Integration** - Word-level audio transcription with precise timing
4. **Visual Analysis** - FFmpeg frame extraction + AI visual description
5. **Smart Summarization** - Automatic footage summary generation
6. **No Manual Configuration** - Zero config files to edit

---

## What You Can Do Next

### Create a Rough Cut
```plaintext
You: "Create a rough cut showing the best moments from the reception"

Claude: [Uses timeline skill]
  - Reads all audio transcripts
  - Proposes story structure for your approval
  - Selects clips based on your direction
  - Generates rough cut YAML and exports to FCPXML

Result: timeline_2025-11-10.fcpxml ready to import into Final Cut Pro
```

### Query Your Footage
```plaintext
You: "Show me all clips where people are talking about the venue"
You: "Create a rough cut of all the clips with people giving the bride and groom well wishes or advice"
You: "Find all the clips that have people giving speeches"
```

Claude can search through transcripts and make selections.

---

## Technical Details

### File Formats Supported
- Any format supported by FFmpeg and your respective editor

---

**ButterCut + Claude Code workflow:**
1. Point Claude at your footage
2. Claude analyzes everything automatically
3. Ask Claude for what you want
4. Import sequence/rough cut into your editor
