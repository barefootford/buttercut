# frozen_string_literal: true

# ffprobe-shaped metadata for generator specs without touching real media:
# build_metadata fabricates the probe hash, stub_ffprobe serves a path→metadata
# map to every generator instance. Specs needing extra stream fields (rotation,
# timecode) define their own build_metadata, which shadows this one.
module ProbeMetadata
  def build_metadata(duration_seconds:, frame_rate: '25/1', width: 1280, height: 720, sample_rate: '48000')
    {
      'streams' => [
        { 'codec_type' => 'video', 'width' => width, 'height' => height,
          'r_frame_rate' => frame_rate, 'color_space' => 'bt709' },
        { 'codec_type' => 'audio', 'sample_rate' => sample_rate }
      ],
      'format' => { 'duration' => duration_seconds.to_s, 'tags' => {} }
    }
  end

  def stub_ffprobe(metadata_by_path)
    allow_any_instance_of(ButterCut::EditorBase).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
      metadata_by_path.fetch(path)
    end
  end
end

RSpec.configure { |config| config.include ProbeMetadata }
