# frozen_string_literal: true

require 'spec_helper'

# Resolve rides the FCPX generator (resolve_core.rb) as a pure pass-through.
# The bare-decibel volume amounts Resolve's importer requires ("-96", never
# "-96db") come from the shared generator, so these examples guard the
# contract Resolve imports depend on.
RSpec.describe ButterCut::Resolve do
  let(:video_path) { '/tmp/resolve_spec.mov' }

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

  it 'subclasses the FCPX generator' do
    expect(described_class).to be < ButterCut::FCPX
  end

  it 'mutes a clip with a bare -96 adjust-volume, keeping its audio on the timeline' do
    xml = described_class.new([{ path: video_path, start_at: 0.0, duration: 2.0, mute: true }]).to_xml

    expect(xml).to match(/<asset-clip name="resolve_spec\.mov"[^>]*audioRole="dialogue"/)
    expect(xml).to include('<adjust-volume amount="-96"/>')
    expect(xml).not_to include('db"')
  end

  it 'gives unmuted clips the bare standard mix level' do
    xml = described_class.new([{ path: video_path, start_at: 0.0, duration: 2.0 }]).to_xml

    expect(xml).to match(/<asset-clip name="resolve_spec\.mov"[^>]*audioRole="dialogue"/)
    expect(xml).to include('<adjust-volume amount="-13.1"/>')
    expect(xml).not_to include('db"')
  end
end
