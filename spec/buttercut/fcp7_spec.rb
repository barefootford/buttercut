require 'spec_helper'

RSpec.describe ButterCut::FCP7 do
  let(:clip_a_path) { '/tmp/fcp7_clip_a.mov' }
  let(:clip_b_path) { '/tmp/fcp7_clip_b.mov' }

  def build_metadata(duration_seconds:, frame_rate:, width: 1920, height: 1080, sample_rate: '48000', timecode: nil)
    video_stream = {
      'codec_type' => 'video',
      'width' => width,
      'height' => height,
      'r_frame_rate' => frame_rate,
      'color_space' => 'bt709',
      'color_primaries' => 'bt709',
      'color_transfer' => 'bt709'
    }

    audio_stream = {
      'codec_type' => 'audio',
      'sample_rate' => sample_rate
    }

    {
      'streams' => [video_stream, audio_stream],
      'format' => {
        'duration' => duration_seconds.to_s,
        'tags' => timecode ? { 'timecode' => timecode } : {}
      }
    }
  end

  let(:metadata_by_path) do
    {
      clip_a_path => build_metadata(
        duration_seconds: 4.0,
        frame_rate: '25/1',
        timecode: '01:00:00:00'
      ),
      clip_b_path => build_metadata(
        duration_seconds: 3.0,
        frame_rate: '25/1',
        timecode: '01:02:00:00'
      )
    }
  end

  before do
    allow_any_instance_of(described_class).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
      metadata_by_path.fetch(path)
    end
  end

  describe '#initialize' do
    it 'raises an error when no clips are provided' do
      expect { described_class.new([]) }.to raise_error(ArgumentError)
    end

    it 'accepts absolute clip paths' do
      expect { described_class.new([{ path: clip_a_path }]) }.not_to raise_error
    end
  end

  describe '#to_xml' do
    let(:generator) do
      described_class.new([
        { path: clip_a_path },
        { path: clip_b_path, start_at: 1.0, duration: 2.0 }
      ])
    end

    it 'generates xmeml version 5 XML' do
      xml = generator.to_xml
      expect(xml).to include('<xmeml version="5">')
      expect(xml).to include('<sequence id="sequence-')
      expect(xml).to include('<clipitem id="clipitem-video-1">')
      expect(xml).to include('<clipitem id="clipitem-audio-2">')
    end

    it 'places clips sequentially with correct timeline math' do
      xml = generator.to_xml

      # First clip: full 4 seconds at 25fps => 100 frames
      expect(xml).to match(/<clipitem id="clipitem-video-1">.*?<start>0<\/start>.*?<end>100<\/end>/m)

      # Second clip: starts after 100 frames, trimmed to 2 seconds (50 frames) starting 1s (25 frames) into source
      expect(xml).to match(/<clipitem id="clipitem-video-2">.*?<start>100<\/start>.*?<end>150<\/end>.*?<in>25<\/in>.*?<out>75<\/out>/m)
    end

    it 'includes source file metadata and file:// URLs' do
      xml = generator.to_xml
      expect(xml).to include("file:///tmp/fcp7_clip_a.mov")
      expect(xml).to include("file:///tmp/fcp7_clip_b.mov")
      expect(xml).to include('<width>1920</width>')
      expect(xml).to include('<height>1080</height>')
    end

    it 'honors embedded timecode when present' do
      xml = generator.to_xml
      # 01:00:00:00 @ 25fps => 90000 frames
      expect(xml).to include('<frame>90000</frame>')
    end
  end
end
