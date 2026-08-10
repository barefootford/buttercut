# frozen_string_literal: true

require 'spec_helper'

# Resolve rides the FCPX generator (resolve_core.rb), diverging only where it
# conforms an import differently. These examples guard the contracts it needs.
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

  # Sony XAVC hangs start timecode off an `rtmd` stream with no timecode track.
  # Final Cut can't read it and needs zero; Resolve reads it and needs the match.
  context 'with timecode on a Sony rtmd metadata stream and no timecode track' do
    let(:rtmd_path) { '/tmp/sony_C0055.MP4' }

    let(:metadata) do
      {
        'streams' => [
          { 'codec_type' => 'video', 'codec_name' => 'h264',
            'width' => 1920, 'height' => 1080, 'r_frame_rate' => '50/1',
            'color_space' => 'bt709', 'color_primaries' => 'bt709', 'color_transfer' => 'bt709' },
          { 'codec_type' => 'audio', 'sample_rate' => '48000' },
          { 'codec_type' => 'data', 'codec_tag_string' => 'rtmd', 'index' => 2,
            'tags' => { 'timecode' => '18:07:16:04' } }
        ],
        'format' => { 'duration' => '20.64', 'tags' => {} }
      }
    end

    it 'anchors to the timecode Resolve can read' do
      generator = described_class.new([{ path: rtmd_path }])

      expect(generator.clip_timecode_string(rtmd_path)).to eq('18:07:16:04')
      # 18:07:16:04 at 50 fps — 3_261_804 frames ÷ 50, reduced.
      expect(generator.clip_timecode_fraction(rtmd_path)).to eq('1630902/25s')
    end

    it 'anchors the asset and asset-clip so the pool clip links' do
      generator = described_class.new([{ path: rtmd_path }])
      xml = generator.to_xml

      expect(xml).to match(%r{<asset id="[^"]+"[^>]*start="1630902/25s"})
      expect(xml).to match(%r{<asset-clip[^>]*start="1630902/25s"})
    end

    it 'leaves Final Cut anchored at zero for the same clip' do
      generator = ButterCut::FCPX.new([{ path: rtmd_path }])

      expect(generator.clip_timecode_string(rtmd_path)).to be_nil
      expect(generator.clip_timecode_fraction(rtmd_path)).to eq('0s')
    end
  end
end
