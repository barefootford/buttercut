# ButterCut

![Very real butter dish](very-real-butter-dish.jpg)

## Edit video with Claude Code
ButterCut analyzes footage and builds roughcuts or sequences for Final Cut Pro and Adobe Premiere.

Two pieces work together to make this go: ButterCut, The Ruby gem. And ButterCut, the Claude Code Skills.

The Skills (library, transcribe-audio, analyze-video, and roughcut) analyze and index your videos. These are done through **Libraries** which contain paths to your footage, json audio transcripts, 'visual' transcripts and some state in library.yaml. After transcripts are generated, the skills can build a narrative by reading visual trancripts and then creating a yaml rough cut.

ButterCut, the Ruby Gem, takes these clips with timings and builds XML.

It's fun and makes editing feel a bit like how we've been programming this year.

ButterCut was inspired by ambitious open source work from [Chris Hocking](https://github.com/CommandPost/CommandPost) and [Andrew Arrow](https://github.com/andrewarrow/cutlass/tree/main).

## Requirements
- Ruby 3.3.6 (xml generation and file massaging)
- Python 3.12.8 (WhisperX)
- FFmpeg (video frame and metadata extraction)
- WhisperX (transcribe footage with word level timing)
- mise (version manager)
- Claude Code (though you could probably shove this into Codex too)

## Installation

**Note:** Claude Code can probably handle all of this for you.
Use Claude Code's built-in installation check:
```plaintext
You: "Check if my installation is set up correctly"
Claude: [Runs installation-check skill to verify dependencies]
```

### Prerequisites

1. **Install mise** (if not already installed):
   ```bash
   curl https://mise.run | sh
   # Or with Homebrew:
   brew install mise
   ```

2. **Install FFmpeg**:
   ```bash
   brew install ffmpeg
   ```

### Setup Steps

1. **Navigate to the project directory**:
   ```bash
   cd buttercut
   ```

2. **Install Ruby and Python** (mise reads `.mise.toml` automatically):
   ```bash
   mise install
   ```

   This installs:
   - Ruby 3.3.6
   - Python 3.12.8

3. **Install Ruby dependencies**:
   ```bash
   bundle install
   ```

4. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

### Verify Installation

You can verify everything is set up correctly:

```bash
# Check Ruby version
ruby --version  # Should show: ruby 3.3.6

# Check Python version
python --version  # Should show: Python 3.12.8

# Check FFmpeg
ffmpeg -version

# Check WhisperX
whisperx --help
```

## Supported Editors

| Editor Symbol | Format | Typical Import Target |
| ------------- | ------ | --------------------- |
| `:fcpx`       | FCPXML 1.8 | Final Cut Pro X |
| `:fcp7`       | xmeml version 5 | Final Cut Pro 7 / Adobe Premiere Pro |

## Usage

### Quick Start: Adding a Video Library

Want to analyze footage with Claude Code? Here's the basic workflow:

```plaintext
You: "I want to build a new library"

Claude: [Launches library skill and asks for details]

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

### Basic XML Generation

```ruby
require 'buttercut'

# Create a 3-clip timeline with 3 seconds from each video
videos = [
  { path: '/path/to/video1.mp4', duration: 3.0 },
  { path: '/path/to/video2.mp4', duration: 3.0, start_at: 30.0 },
  { path: '/path/to/video3.mp4', duration: 3.0, start_at: 2.0 }
]

# Final Cut Pro X timeline
fcpx_generator = ButterCut.new(videos, editor: :fcpx)
fcpx_generator.save('timeline.fcpxml')

# Final Cut Pro 7 / Adobe Premiere timeline
# This opened up correctly for me, but this isn't really tested yet.
fcp7_generator = ButterCut.new(videos, editor: :fcp7)
fcp7_generator.save('timeline.xml')
```

### Clip Options

Each clip in the array is a hash with the following keys:

- **`path`** (required): Absolute path to the video file
- **`start_at`** (optional): Where in the source file to start reading (default: 0.0)
  - Trims the beginning of the video
  - Specified as seconds (float)
  - Examples: `2.0` (2 seconds), `1.5` (1.5 seconds)
  - Automatically rounded to nearest frame boundary for precision
- **`duration`** (optional): How much of the source to use (default: full video from start_at)
  - Specified as seconds (float)
  - Examples: `5.0` (5 seconds), `3.5` (3.5 seconds)
  - If not specified and `start_at` is provided, uses remaining video after trim
  - Automatically rounded to nearest frame boundary for precision

### Roughcut Workflow with Claude Code

ButterCut includes Claude Code skills for intelligent video editing:

1. **Library Management** - Organize video projects
2. **Audio Transcription** - WhisperX integration for word-level timing
3. **Visual Analysis** - Frame extraction and AI analysis
4. **Rough Cut Creation** - AI-generated rough cuts based on transcripts

See `CLAUDE.md` for detailed workflow documentation.

## Testing

```bash
# Install dependencies
bundle install

# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/buttercut_spec.rb
```

## DTD Validation

Validate FCPXML files against the DTD specification:

```bash
xmllint --dtdvalid "dtd/FCPXMLv1_8.dtd" "path/to/your/file.fcpxml"
```

## License

MIT

## Contributing

Bug reports and pull requests welcome.
