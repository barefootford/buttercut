# frozen_string_literal: true

require 'spec_helper'

# ResolveLegacy is the temporary FCP7-xmeml fallback for editors who hit
# import trouble with the FCPXML-based ButterCut::Resolve (see
# resolve_legacy_core.rb) — a pure pass-through, same as Resolve was before
# the FCPXML migration.
RSpec.describe ButterCut::ResolveLegacy do
  let(:video_path) { '/tmp/resolve_legacy_spec.mov' }

  let(:metadata) do
    {
      'streams' => [
        { 'codec_type' => 'video', 'codec_name' => 'h264',
          'width' => 1920, 'height' => 1080, 'r_frame_rate' => '24/1',
          'color_space' => 'bt709', 'color_primaries' => 'bt709', 'color_transfer' => 'bt709' },
        { 'codec_type' => 'audio', 'sample_rate' => '48000' }
      ],
      'format' => { 'duration' => '4.0', 'tags' => {} }
    }
  end

  before do
    allow_any_instance_of(ButterCut::EditorBase)
      .to receive(:extract_metadata_from_ffprobe).and_return(metadata)
  end

  it 'subclasses the FCP7 generator' do
    expect(described_class).to be < ButterCut::FCP7
  end

  it 'writes xmeml version 5' do
    xml = described_class.new([{ path: video_path, start_at: 0.0, duration: 2.0 }]).to_xml

    expect(xml).to include('<xmeml version="5">')
  end

  it 'mutes a clip with a level-0 Audio Levels filter' do
    xml = described_class.new([{ path: video_path, start_at: 0.0, duration: 2.0, mute: true }]).to_xml

    expect(xml).to include('<effectid>audiolevels</effectid>')
    expect(xml).to match(%r{<parameterid>level</parameterid>\s*<name>Level</name>.*?<value>0</value>}m)
  end
end
