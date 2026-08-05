require_relative 'fcpx'

class ButterCut
  # DaVinci Resolve timeline export. The XML is the FCPX generator's, unchanged
  # — Resolve reads FCPXML 1.12 — but the source-timecode anchor diverges.
  class Resolve < FCPX
    # Resolve reads timecode off the file with or without a track, and links an
    # import by matching pool timecode — a zero anchor lands every clip offline.
    def untracked_timecode_string(video_path)
      stream_timecode_string(video_path) || format_timecode_string(video_path)
    end
  end
end
