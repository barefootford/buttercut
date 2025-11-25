# Basic XML Generation

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

# Final Cut Pro 7 / Adobe Premiere / DaVinci Resolve timeline
fcp7_generator = ButterCut.new(videos, editor: :fcp7)
fcp7_generator.save('timeline.xml')
```

## Clip Options

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
