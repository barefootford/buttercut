# ButterCut
## Claude Code rough cut and sequence editor
ButterCut builds rough cuts and sequences for Final Cut Pro. (I have an initial go at adding support for Adobe Premiere through Final Cut Pro 7 files. But it's well-tested at the moment.) Two pieces work together to make this go. The first is ButterCut, The Ruby Gem. The gem takes an array of clips and then builds XML for your video editor. The second piece is several Claude Code Skills that together can analyze and index your video and then be used to create simple sequential video cuts in yaml.

With both, you can get a whole rough cut going. It's fun and makes editing feel a bit like how we've been programming the past year.

## Features

- **XML Generation**: Create FCPXML and FCP7/Premiere XML from video file paths
- **Automatic Metadata Extraction**: Uses FFmpeg to extract video properties (duration, resolution, frame rate, audio rate, etc.)
- **AI-Powered Workflow**: Includes Claude Code skills for transcription, visual analysis, and rough cut creation
- **Library Management**: Organize video projects into libraries with persistent memory
- **No Manual Configuration**: Just provide file paths and get working XML

## Requirements

- Ruby >= 2.7.0
- FFmpeg (for metadata extraction)
- WhisperX (optional, for audio transcription)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'buttercut'
```

Or install it yourself as:

```bash
gem install buttercut
```

For local development:

```bash
cd buttercut
bundle install
```

## Supported Editors

| Editor Symbol | Format | Typical Import Target |
| ------------- | ------ | --------------------- |
| `:fcpx`       | FCPXML 1.8 | Final Cut Pro X |
| `:fcp7`       | xmeml version 5 | Final Cut Pro 7 / Adobe Premiere Pro |

## Usage

### Basic XML Generation

```ruby
require 'buttercut'

# Create a 3-clip timeline with 3 seconds from each video
videos = [
  { path: '/path/to/video1.mp4', duration: 3.0 },
  { path: '/path/to/video2.mp4', duration: 3.0 },
  { path: '/path/to/video3.mp4', duration: 3.0 }
]

# Final Cut Pro X timeline
fcpx_generator = ButterCut.new(videos, editor: :fcpx)
fcpx_generator.save('timeline.fcpxml')

# Final Cut Pro 7 / Adobe Premiere timeline
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

### AI-Powered Workflow with Claude Code

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

## Design Philosophy

ButterCut is designed to be simple and automatic:
- **Input**: Array of full file paths to video files
- **Output**: Working FCPXML ready to import into Final Cut Pro
- **Automatic Metadata Extraction**: Uses FFmpeg internally to extract video properties
- **No Manual Configuration Required**: Library handles all the complexity of FCPXML generation

The user should not need to understand video codecs, frame rates, or FCPXML structure - just provide file paths and get working XML.

## License

MIT

## Contributing

Bug reports and pull requests welcome.
