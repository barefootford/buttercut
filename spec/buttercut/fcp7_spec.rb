require 'spec_helper'

RSpec.describe ButterCut::FCP7 do
  let(:clip_a_path) { '/tmp/fcp7_clip_a.mov' }
  let(:clip_b_path) { '/tmp/fcp7_clip_b.mov' }

  def build_metadata(duration_seconds:, frame_rate:, width: 1920, height: 1080, sample_rate: '48000', timecode: nil, rotation: nil)
    video_stream = {
      'codec_type' => 'video',
      'width' => width,
      'height' => height,
      'r_frame_rate' => frame_rate,
      'color_space' => 'bt709',
      'color_primaries' => 'bt709',
      'color_transfer' => 'bt709'
    }

    # Add rotation metadata (common in mobile video)
    if rotation
      video_stream['side_data_list'] = [{ 'rotation' => rotation }]
    end

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

  describe 'sequence_frame_rate option' do
    let(:generator) do
      described_class.new(
        [{ path: clip_a_path }],
        sequence_frame_rate: 50
      )
    end

    it 'overrides timeline frame rate' do
      xml = generator.to_xml
      expect(xml).to include('<timebase>50</timebase>')
    end

    it 'uses custom frame rate for duration calculations' do
      xml = generator.to_xml
      # 4 seconds at 50fps = 200 frames
      expect(xml).to match(/<duration>200<\/duration>/)
    end
  end

  describe 'sequence dimensions options' do
    let(:generator) do
      described_class.new(
        [{ path: clip_a_path }],
        sequence_width: 1080,
        sequence_height: 1920
      )
    end

    it 'uses custom sequence dimensions' do
      xml = generator.to_xml
      # Sequence format should use custom dimensions
      expect(xml).to match(/<samplecharacteristics>.*?<width>1080<\/width>.*?<height>1920<\/height>/m)
    end
  end

  describe 'windows_file_paths option' do
    let(:wsl_clip_path) { '/mnt/d/Videos/clip.mov' }

    let(:wsl_metadata) do
      {
        wsl_clip_path => build_metadata(
          duration_seconds: 4.0,
          frame_rate: '25/1'
        )
      }
    end

    before do
      allow_any_instance_of(described_class).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
        wsl_metadata.fetch(path)
      end
    end

    it 'converts WSL paths to Windows format when enabled' do
      generator = described_class.new(
        [{ path: wsl_clip_path }],
        windows_file_paths: true
      )
      xml = generator.to_xml
      expect(xml).to include('file://localhost/D:/Videos/clip.mov')
    end

    it 'keeps Linux paths by default' do
      generator = described_class.new([{ path: wsl_clip_path }])
      xml = generator.to_xml
      expect(xml).to include('file:///mnt/d/Videos/clip.mov')
    end
  end

  describe 'motion filter for portrait sequences' do
    let(:landscape_clip_path) { '/tmp/landscape.mov' }
    let(:portrait_clip_path) { '/tmp/portrait.mov' }

    let(:portrait_metadata) do
      {
        landscape_clip_path => build_metadata(
          duration_seconds: 4.0,
          frame_rate: '30/1',
          width: 1920,
          height: 1080
        ),
        portrait_clip_path => build_metadata(
          duration_seconds: 4.0,
          frame_rate: '30/1',
          width: 1080,
          height: 1920,
          rotation: 90
        )
      }
    end

    before do
      allow_any_instance_of(described_class).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
        portrait_metadata.fetch(path)
      end
    end

    it 'adds motion filter for landscape clips in portrait sequence' do
      generator = described_class.new(
        [{ path: landscape_clip_path }],
        sequence_width: 1080,
        sequence_height: 1920
      )
      xml = generator.to_xml
      expect(xml).to include('<effect>')
      expect(xml).to include("<name>Basic Motion</name>")
      expect(xml).to include("<parameterid>scale</parameterid>")
    end

    it 'calculates correct scale for center crop (fill height)' do
      generator = described_class.new(
        [{ path: landscape_clip_path }],
        sequence_width: 1080,
        sequence_height: 1920
      )
      xml = generator.to_xml
      # 1920 / 1080 * 100 = 177.78% scale to fill height
      expect(xml).to match(/<value>177\.78<\/value>/)
    end

    it 'adds motion filter for clips with rotation metadata' do
      generator = described_class.new(
        [{ path: portrait_clip_path }],
        sequence_width: 1080,
        sequence_height: 1920
      )
      xml = generator.to_xml
      expect(xml).to include('<effect>')
      expect(xml).to include("<name>Basic Motion</name>")
    end

    it 'applies correct rotation for portrait clips (rotation=90 becomes -90 in FCP7)' do
      generator = described_class.new(
        [{ path: portrait_clip_path }],
        sequence_width: 1080,
        sequence_height: 1920
      )
      xml = generator.to_xml
      expect(xml).to include("<parameterid>rotation</parameterid>")
      # rotation=90 in metadata should become -90 in FCP7 (clockwise)
      expect(xml).to match(/<parameterid>rotation<\/parameterid>.*?<value>-90<\/value>/m)
    end
  end

  describe 'audio_track option' do
    let(:music_path) { '/tmp/music.m4a' }

    let(:music_metadata) do
      {
        clip_a_path => build_metadata(
          duration_seconds: 4.0,
          frame_rate: '25/1'
        ),
        music_path => {
          'streams' => [
            {
              'codec_type' => 'audio',
              'sample_rate' => '44100'
            }
          ],
          'format' => {
            'duration' => '180.0'  # 3 minutes
          }
        }
      }
    end

    before do
      allow_any_instance_of(described_class).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
        music_metadata.fetch(path)
      end
    end

    it 'adds a second audio track for music' do
      generator = described_class.new(
        [{ path: clip_a_path }],
        audio_track: music_path
      )
      xml = generator.to_xml
      # Should have two audio tracks
      expect(xml.scan(/<track>/).count).to eq(3)  # 1 video + 2 audio tracks
    end

    it 'includes music file metadata' do
      generator = described_class.new(
        [{ path: clip_a_path }],
        audio_track: music_path
      )
      xml = generator.to_xml
      expect(xml).to include('clipitem-music-1')
      expect(xml).to include('file://') # music file URL
    end

    it 'trims music to sequence duration when longer' do
      generator = described_class.new(
        [{ path: clip_a_path }],  # 4 seconds
        audio_track: music_path   # 180 seconds
      )
      xml = generator.to_xml
      # Music should be trimmed to 4 seconds (100 frames at 25fps)
      expect(xml).to match(/<clipitem id="clipitem-music-1">.*?<duration>100<\/duration>/m)
    end

    it 'does not add music track when audio_track not specified' do
      generator = described_class.new([{ path: clip_a_path }])
      xml = generator.to_xml
      expect(xml).not_to include('clipitem-music')
      expect(xml.scan(/<track>/).count).to eq(2)  # 1 video + 1 audio track
    end

    it 'offsets music in/out when audio_start is specified' do
      generator = described_class.new(
        [{ path: clip_a_path }],  # 4 seconds at 25fps
        audio_track: music_path,
        audio_start: 10.0         # skip first 10 seconds
      )
      xml = generator.to_xml
      # 10 seconds at 25fps = 250 frames offset
      expect(xml).to match(/<clipitem id="clipitem-music-1">.*?<in>250<\/in>/m)
      expect(xml).to match(/<clipitem id="clipitem-music-1">.*?<out>350<\/out>/m)
    end

    it 'uses zero offset when audio_start is not specified' do
      generator = described_class.new(
        [{ path: clip_a_path }],
        audio_track: music_path
      )
      xml = generator.to_xml
      expect(xml).to match(/<clipitem id="clipitem-music-1">.*?<in>0<\/in>/m)
    end
  end
end
