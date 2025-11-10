require 'spec_helper'

RSpec.describe ButterCut::FCPX do
  let(:video_file_path) { '/Users/andrew/code/buttercut/media/MVI_0323_720p.mov' }
  let(:clips) { [{ path: video_file_path }] }
  let(:gh5_video_path) { File.expand_path('../../media/P1044376_timecode_fixture.mov', __dir__) }

  def build_metadata(frame_rate:, duration_seconds:, width: 1280, height: 720, sample_rate: '48000', timecode: nil)
    video_stream = {
      'codec_type' => 'video',
      'width' => width,
      'height' => height,
      'r_frame_rate' => frame_rate,
      'color_space' => 'bt709',
      'color_primaries' => 'bt709',
      'color_transfer' => 'bt709'
    }
    video_stream['tags'] = { 'timecode' => timecode } if timecode

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

  def stub_uuid_sequence(generator, uuids)
    sequence = uuids.dup
    allow(generator).to receive(:generate_uuid) do
      raise "UUID sequence exhausted" if sequence.empty?
      sequence.shift
    end
  end

  def expected_full_xml(fixture_name, generator, media_paths)
    fixture_path = File.expand_path("../fixtures/#{fixture_name}.fcpxml", __dir__)
    content = File.read(fixture_path)

    replacements = {
      '__SRC_MVI_0309__' => generator.path_to_file_url(media_paths[0]),
      '__SRC_MVI_0323__' => generator.path_to_file_url(media_paths[1]),
      '__SRC_P1044376__' => generator.path_to_file_url(media_paths[2])
    }

    project_basename = File.basename(media_paths.first, File.extname(media_paths.first))
    timestamped_project_name = "#{project_basename} #{generator.send(:timestamp_suffix)}"
    event_label = project_basename

    asset_id_placeholders = {
      '__ASSET_ID_MVI_0309__' => asset_id_for(generator, media_paths[0]),
      '__ASSET_ID_MVI_0323__' => asset_id_for(generator, media_paths[1]),
      '__ASSET_ID_GH5__' => asset_id_for(generator, media_paths[2])
    }

    asset_uid_placeholders = {
      '__ASSET_UID_MVI_0309__' => asset_uid_for(generator, media_paths[0]),
      '__ASSET_UID_MVI_0323__' => asset_uid_for(generator, media_paths[1]),
      '__ASSET_UID_GH5__' => asset_uid_for(generator, media_paths[2])
    }

    replacements.merge!(
      '__EVENT_LABEL__' => event_label,
      '__PROJECT_LABEL__' => timestamped_project_name,
      '__ASSET_ID_MVI_0309__' => asset_id_placeholders['__ASSET_ID_MVI_0309__'],
      '__ASSET_ID_MVI_0323__' => asset_id_placeholders['__ASSET_ID_MVI_0323__'],
      '__ASSET_ID_GH5__' => asset_id_placeholders['__ASSET_ID_GH5__'],
      '__ASSET_UID_MVI_0309__' => asset_uid_placeholders['__ASSET_UID_MVI_0309__'],
      '__ASSET_UID_MVI_0323__' => asset_uid_placeholders['__ASSET_UID_MVI_0323__'],
      '__ASSET_UID_GH5__' => asset_uid_placeholders['__ASSET_UID_GH5__']
    )

    replacements.each { |placeholder, value| content.gsub!(placeholder, value) }
    content
  end

  def asset_id_for(generator, path)
    abs_path = generator.get_absolute_path(path)
    generator.send(:deterministic_asset_id, abs_path)
  end

  def asset_uid_for(generator, path)
    abs_path = generator.get_absolute_path(path)
    generator.send(:deterministic_asset_uid, abs_path)
  end

  describe 'deterministic asset identifiers' do
    it 'returns consistent asset ids and uids per path' do
      generator = ButterCut::FCPX.new(clips)
      abs_path = generator.get_absolute_path(video_file_path)
      id1 = generator.send(:deterministic_asset_id, abs_path)
      id2 = generator.send(:deterministic_asset_id, abs_path)
      uid1 = generator.send(:deterministic_asset_uid, abs_path)
      uid2 = generator.send(:deterministic_asset_uid, abs_path)

      expect(id1).to eq(id2)
      expect(uid1).to eq(uid2)
    end
  end

  describe '#initialize' do
    it 'creates a new ButterCut::FCPX instance' do
      generator = ButterCut::FCPX.new(clips)
      expect(generator).to be_a(ButterCut::FCPX)
    end

    it 'raises error when no clips provided' do
      expect { ButterCut::FCPX.new([]) }.to raise_error(ArgumentError, "No clips provided")
      expect { ButterCut::FCPX.new(nil) }.to raise_error(ArgumentError, "No clips provided")
    end

    it 'stores clips' do
      generator = ButterCut::FCPX.new(clips)
      expect(generator.clips).to eq(clips)
    end

    it 'raises error when clip is not a hash' do
      expect { ButterCut::FCPX.new(['string']) }.to raise_error(ArgumentError, /must be a hash/)
    end

    it 'raises error when clip missing path key' do
      expect { ButterCut::FCPX.new([{ start_at: '2s' }]) }.to raise_error(ArgumentError, /must have a 'path' key/)
    end

    it 'raises error when video paths are not absolute' do
      expect { ButterCut::FCPX.new([{ path: 'relative/path/video.mp4' }]) }.to raise_error(ArgumentError, /must be absolute paths/)
      expect { ButterCut::FCPX.new([{ path: 'video.mp4' }]) }.to raise_error(ArgumentError, /must be absolute paths/)
      expect { ButterCut::FCPX.new([{ path: '/absolute/path/video.mp4' }, { path: 'relative.mp4' }]) }.to raise_error(ArgumentError, /must be absolute paths/)
    end

    it 'accepts absolute paths' do
      expect { ButterCut::FCPX.new([{ path: video_file_path }]) }.not_to raise_error
      expect { ButterCut::FCPX.new([{ path: video_file_path }, { path: video_file_path }]) }.not_to raise_error
    end
  end

  describe 'timecode-aware clips' do
    let(:gh5_generator) { ButterCut::FCPX.new([{ path: gh5_video_path }]) }

    it 'extracts embedded SMPTE timecode from camera metadata' do
      expect(gh5_generator.clip_timecode_string(gh5_video_path)).to eq('21:44:10:09')
    end

    it 'converts embedded timecode into FCPXML fractional start' do
      expect(gh5_generator.clip_timecode_fraction(gh5_video_path)).to eq('626629003/8000s')
    end

    it 'anchors asset-clip start to the embedded timecode when no trim is applied' do
      xml = gh5_generator.to_xml

      expect(xml).to include(%(start="#{gh5_generator.clip_timecode_fraction(gh5_video_path)}"))
    end

    it 'includes start attribute on asset element matching the embedded timecode' do
      xml = gh5_generator.to_xml
      timecode = gh5_generator.clip_timecode_fraction(gh5_video_path)
      asset_id = asset_id_for(gh5_generator, gh5_video_path)

      # Verify asset element has start attribute
      expect(xml).to match(/<asset id="#{Regexp.escape(asset_id)}"[^>]*start="#{Regexp.escape(timecode)}"/)
    end

    it 'offsets trims relative to the embedded timecode' do
      trim = '1001/24000s' # exactly one frame at 23.976 fps
      generator = ButterCut::FCPX.new([{ path: gh5_video_path, start_at: trim }])
      xml = generator.to_xml

      base_timecode = gh5_generator.clip_timecode_fraction(gh5_video_path)
      expected_start = gh5_generator.add_fractions(base_timecode, trim)
      expect(xml).to include(%(start="#{expected_start}"))
    end

    it 'ensures asset and asset-clip start values align with embedded timecode' do
      xml = gh5_generator.to_xml
      timecode = gh5_generator.clip_timecode_fraction(gh5_video_path)
      asset_id = asset_id_for(gh5_generator, gh5_video_path)

      # Asset element should have start matching timecode
      expect(xml).to match(/<asset id="#{Regexp.escape(asset_id)}"[^>]*start="#{Regexp.escape(timecode)}"/)

      # Asset-clip element should have start matching timecode (when not trimmed)
      expect(xml).to match(/<asset-clip[^>]*start="#{Regexp.escape(timecode)}"/)
    end

    context 'with drop-frame camera timecode' do
      let(:drop_frame_path) { '/tmp/drop_frame.mov' }
      let(:drop_frame_metadata) do
        build_metadata(
          frame_rate: '30000/1001',
          duration_seconds: 120.0,
          timecode: '01:00:00;00'
        )
      end

      before do
        allow_any_instance_of(ButterCut::FCPX).to receive(:extract_metadata_from_ffprobe).and_return(drop_frame_metadata)
      end

      it 'converts drop-frame timecode into the correct fractional start' do
        generator = ButterCut::FCPX.new([{ path: drop_frame_path }])
        expect(generator.clip_timecode_fraction(drop_frame_path)).to eq('8999991/2500s')
      end

      it 'keeps asset and clip start attributes aligned to the drop-frame timecode' do
        generator = ButterCut::FCPX.new([{ path: drop_frame_path }])
        xml = generator.to_xml
        asset_id = asset_id_for(generator, drop_frame_path)

        expect(xml).to match(/<asset id="#{Regexp.escape(asset_id)}"[^>]*start="8999991\/2500s"/)
        expect(xml).to match(/<asset-clip[^>]*start="8999991\/2500s"/)
      end
    end
  end

  describe '#generate_uuid' do
    it 'generates a valid UUID' do
      generator = ButterCut::FCPX.new(clips)
      uuid = generator.generate_uuid
      # UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      expect(uuid).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
    end

    it 'generates unique UUIDs' do
      generator = ButterCut::FCPX.new(clips)
      uuid1 = generator.generate_uuid
      uuid2 = generator.generate_uuid
      expect(uuid1).not_to eq(uuid2)
    end
  end

  describe '#gcd' do
    it 'calculates greatest common divisor' do
      generator = ButterCut::FCPX.new(clips)
      expect(generator.gcd(48, 18)).to eq(6)
      expect(generator.gcd(100, 50)).to eq(50)
      expect(generator.gcd(17, 19)).to eq(1)
    end
  end

  describe '#add_fractions' do
    it 'adds two fractions and simplifies' do
      generator = ButterCut::FCPX.new(clips)
      result = generator.add_fractions("1/2s", "1/3s")
      expect(result).to eq("5/6s")
    end

    it 'adds fractions with different denominators' do
      generator = ButterCut::FCPX.new(clips)
      result = generator.add_fractions("260260/24000s", "1369368/24000s")
      expect(result).to eq("407407/6000s")
    end
  end

  describe '#get_filename' do
    it 'extracts filename from path' do
      generator = ButterCut::FCPX.new(clips)
      expect(generator.get_filename('/path/to/video.mp4')).to eq('video.mp4')
      expect(generator.get_filename('video.mp4')).to eq('video.mp4')
    end
  end

  describe '#get_basename' do
    it 'extracts basename without extension' do
      generator = ButterCut::FCPX.new(clips)
      expect(generator.get_basename('video.mp4')).to eq('video')
      expect(generator.get_basename('my_video.MP4')).to eq('my_video')
    end
  end

  describe '#get_absolute_path' do
    it 'converts relative path to absolute' do
      generator = ButterCut::FCPX.new(clips)
      abs_path = generator.get_absolute_path('test.mp4')
      expect(abs_path).to start_with('/')
      expect(abs_path).to end_with('test.mp4')
    end

    it 'returns absolute path unchanged' do
      generator = ButterCut::FCPX.new(clips)
      abs_path = generator.get_absolute_path('/absolute/path/test.mp4')
      expect(abs_path).to eq('/absolute/path/test.mp4')
    end
  end

  describe '#path_to_file_url' do
    it 'converts path to file:// URL' do
      generator = ButterCut::FCPX.new(clips)
      url = generator.path_to_file_url('test.mp4')
      expect(url).to start_with('file://')
      expect(url).to end_with('test.mp4')
    end

    it 'URL encodes spaces in path' do
      generator = ButterCut::FCPX.new(clips)
      # Create a mock path with space
      allow(generator).to receive(:get_absolute_path).and_return('/path/with space/test.mp4')
      url = generator.path_to_file_url('test.mp4')
      expect(url).to eq('file:///path/with%20space/test.mp4')
    end
  end

  describe '#escape_xml' do
    it 'escapes XML special characters' do
      generator = ButterCut::FCPX.new(clips)
      expect(generator.escape_xml('test & video')).to eq('test &amp; video')
      expect(generator.escape_xml('test < video')).to eq('test &lt; video')
      expect(generator.escape_xml('test > video')).to eq('test &gt; video')
      expect(generator.escape_xml('test "video"')).to eq('test &quot;video&quot;')
      expect(generator.escape_xml("test 'video'")).to eq('test &apos;video&apos;')
    end

    it 'returns empty string for nil' do
      generator = ButterCut::FCPX.new(clips)
      expect(generator.escape_xml(nil)).to eq('')
    end
  end

  describe '#to_xml' do
    it 'generates valid FCPXML' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      xml = generator.to_xml

      expect(xml).to include('<?xml version="1.0" encoding="utf-8"?>')
      expect(xml).to include('<fcpxml version="1.8">')
      expect(xml).to include('</fcpxml>')
    end

    it 'includes start attribute on asset element (defaults to 0s for files without timecode)' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      xml = generator.to_xml
      asset_id = asset_id_for(generator, video_file_path)
      asset_uid = asset_uid_for(generator, video_file_path)

      # Verify asset element has start attribute (should be "0s" for files without embedded timecode)
      expect(xml).to match(/<asset id="#{Regexp.escape(asset_id)}"[^>]*uid="#{Regexp.escape(asset_uid)}"[^>]*start="0s"/)
    end

    it 'assigns deterministic asset uid values' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      xml = generator.to_xml
      asset_uid = asset_uid_for(generator, video_file_path)

      expect(xml).to include(%(uid="#{asset_uid}"))
    end

    it 'includes basic FCPXML structure' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      xml = generator.to_xml
      asset_id = asset_id_for(generator, video_file_path)
      asset_uid = asset_uid_for(generator, video_file_path)

      expect(xml).to include('<resources>')
      expect(xml).to include('<format id="r1"')
      expect(xml).to include(%(<asset id="#{asset_id}" name="MVI_0323_720p.mov" uid="#{asset_uid}"))
      expect(xml).to include('<library location="./">')
      expect(xml).to include('<event name="MVI_0323_720p"')
      expect(xml).to match(/<project name="MVI_0323_720p \d{8}-\d{6}"/)
      expect(xml).to include('<sequence')
      expect(xml).to include('<spine>')
      expect(xml).to include('<asset-clip')
    end

    it 'includes format specifications' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      xml = generator.to_xml

      # Uses actual metadata from video file
      expect(xml).to include('height="720"')
      expect(xml).to include('width="1280"')
      expect(xml).to include('frameDuration="1001/24000s"')
      expect(xml).to include('colorSpace="1-1-1 (Rec. 709)"')
    end

    it 'includes audio settings' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      xml = generator.to_xml

      expect(xml).to include('audioRate="48000"')
      expect(xml).to include('audioRate="48k"')
      expect(xml).to include('<adjust-volume amount="-13.100000000000001db"/>')
    end

    it 'handles multiple video files' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }, { path: video_file_path }])
      xml = generator.to_xml

      # Should have one asset (deduplicated since it's the same file)
      expect(xml.scan(/<asset id="/).length).to eq(1)
      # Should have two asset-clips
      expect(xml.scan(/<asset-clip/).length).to eq(2)
    end

    it 'deduplicates same file used multiple times' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }, { path: video_file_path }])
      xml = generator.to_xml

      # Should have one asset (deduplicated)
      expect(xml.scan(/<asset id="/).length).to eq(1)
      # But two asset-clips (clips reference the same asset)
      expect(xml.scan(/<asset-clip/).length).to eq(2)
    end

    it 'calculates correct sequence duration for multiple clips' do
      # Single clip: initial_offset (0s) + clip_duration = 29029/4800s
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      xml = generator.to_xml
      expect(xml).to include('sequence duration="29029/4800s"')

      # Two clips: 0s + 2*clip_duration = 29029/2400s
      generator = ButterCut::FCPX.new([{ path: video_file_path }, { path: video_file_path }])
      xml = generator.to_xml
      expect(xml).to include('sequence duration="29029/2400s"')
    end

    it 'calculates correct offsets for sequential clips' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }, { path: video_file_path }])
      xml = generator.to_xml

      # First clip should have initial offset (0s)
      expect(xml).to include('offset="0s"')
      # Second clip should have offset = initial_offset + clip_duration
      # 0s + 29029/4800s = 29029/4800s
      expect(xml).to include('offset="29029/4800s"')
    end

    it 'automatically calculates duration when start_at is provided without duration' do
      # Asset duration is 29029/4800s (6.044 seconds)
      # If start_at is 48000/24000s (2 seconds), it gets rounded to nearest frame boundary: 1001/500s (48 frames)
      # Duration is then calculated as asset_duration - start_at_rounded and also rounded to frame boundary
      generator = ButterCut::FCPX.new([{ path: video_file_path, start_at: '48000/24000s' }])
      xml = generator.to_xml

      # start_at should be rounded to frame boundary (48 frames = 1001/500s)
      expect(xml).to include('start="1001/500s"')
      # Duration should be calculated and rounded to frame boundary
      expect(xml).to include('duration="97097/24000s"')
    end

    describe 'multi-rate clip handling' do
      let(:clip_a_path) { '/tmp/clip_a.mov' }
      let(:clip_b_path) { '/tmp/clip_b.mov' }
      let(:metadata_by_path) do
        {
          clip_a_path => build_metadata(
            frame_rate: '24000/1001',
            duration_seconds: 6.0,
            timecode: '00:00:00:00'
          ),
          clip_b_path => build_metadata(
            frame_rate: '30000/1001',
            duration_seconds: 2.0,
            timecode: '00:00:00;00'
          )
        }
      end

      before do
        allow_any_instance_of(ButterCut::FCPX).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
          metadata_by_path.fetch(path)
        end
      end

      it 'rounds trims using each asset frame duration before timeline placement' do
        generator = ButterCut::FCPX.new([
          { path: clip_a_path },
          { path: clip_b_path, start_at: '1001/30000s' }
        ])

        xml = generator.to_xml
        asset_id = asset_id_for(generator, clip_b_path)
        expect(xml).to match(/ref="#{Regexp.escape(asset_id)}"[^>]*start="1001\/30000s"/)
      end
    end
  end

  describe 'full project exports' do
    let(:media_paths) do
      %w[
        MVI_0309_720p.mov
        MVI_0323_720p.mov
        P1044376_timecode_fixture.mov
      ].map { |filename| File.expand_path("../../media/#{filename}", __dir__) }
    end

    let(:uuid_sequence) do
      %w[event-uid project-uid]
    end

    it 'matches the full-clip fixture output' do
      generator = ButterCut::FCPX.new(media_paths.map { |path| { path: path } })
      stub_uuid_sequence(generator, uuid_sequence)

      xml = generator.to_xml
      expected = expected_full_xml('full_media_all_clips', generator, media_paths)

      expect(xml.strip).to eq(expected.strip)
    end

    it 'matches the last-second fixture output' do
      metadata_generator = ButterCut::FCPX.new(media_paths.map { |path| { path: path } })

      last_second_clips = media_paths.map do |path|
        duration_seconds = metadata_generator.video_duration(path)
        start_seconds = [duration_seconds - 1.0, 0].max

        {
          path: path,
          start_at: metadata_generator.seconds_to_fraction(start_seconds),
          duration: metadata_generator.seconds_to_fraction(1.0)
        }
      end

      generator = ButterCut::FCPX.new(last_second_clips)
      stub_uuid_sequence(generator, uuid_sequence)

      xml = generator.to_xml
      expected = expected_full_xml('full_media_last_second', generator, media_paths)

      expect(xml.strip).to eq(expected.strip)
    end
  end

  describe '#save' do
    let(:filename) { 'test_output.fcpxml' }

    after do
      File.delete(filename) if File.exist?(filename)
    end

    it 'saves XML to a file' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      generator.save(filename)

      expect(File.exist?(filename)).to be true
      content = File.read(filename)
      expect(content).to include('<fcpxml version="1.8">')
    end

    it 'saves complete valid FCPXML' do
      generator = ButterCut::FCPX.new([{ path: video_file_path }])
      generator.save(filename)

      content = File.read(filename)
      expect(content).to include('<?xml version="1.0" encoding="utf-8"?>')
      expect(content).to include('<resources>')
      expect(content).to include('<library')
      expect(content).to include('</fcpxml>')
    end
  end
end
