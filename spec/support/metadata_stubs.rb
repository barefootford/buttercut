# frozen_string_literal: true

# Canonical ffprobe stub shapes shared by the exporter specs (FCPX, FCP7,
# Premiere), so "what ffprobe reports for a still / a silent video" has one
# owner instead of a copy per spec file.
module MetadataStubs
  # ffprobe on a still reports a video stream (width/height) but NO audio
  # stream, no usable frame rate, and no duration.
  def image_metadata(width: 1920, height: 1080)
    {
      'streams' => [
        { 'codec_type' => 'video', 'width' => width, 'height' => height,
          'r_frame_rate' => '0/0', 'color_space' => 'bt709' }
      ],
      'format' => { 'duration' => 'N/A', 'tags' => {} }
    }
  end

  # A silent video: real frame rate and duration, but no audio stream.
  def silent_metadata(frame_rate:, duration:)
    {
      'streams' => [
        { 'codec_type' => 'video', 'width' => 1920, 'height' => 1080,
          'r_frame_rate' => frame_rate, 'color_space' => 'bt709' }
      ],
      'format' => { 'duration' => duration, 'tags' => {} }
    }
  end
end

RSpec.configure { |config| config.include MetadataStubs }
