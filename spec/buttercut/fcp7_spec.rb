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

    # A camera reporting a timecode carries a real 'tmcd' track behind it —
    # the track the exporter gates on. See the note in fcpx_spec.rb.
    streams = [video_stream, audio_stream]
    if timecode
      streams << { 'codec_type' => 'data', 'codec_tag_string' => 'tmcd', 'index' => 2,
                   'tags' => { 'timecode' => timecode } }
    end

    {
      'streams' => streams,
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
      expect(xml).to include(file_url_for(clip_a_path))
      expect(xml).to include(file_url_for(clip_b_path))
      expect(xml).to include('<width>1920</width>')
      expect(xml).to include('<height>1080</height>')
    end

    it 'honors embedded timecode when present' do
      xml = generator.to_xml
      # 01:00:00:00 @ 25fps => 90000 frames
      expect(xml).to include('<frame>90000</frame>')
    end

    it 'silences a muted clip with a level-0 audio filter' do
      xml = described_class.new([{ path: clip_a_path, mute: true }]).to_xml
      clipitem = xml[/<clipitem id="clipitem-audio-1">.*?<\/clipitem>/m]

      level = clipitem[/<effectid>audiolevels<\/effectid>.*?<value>(.*?)<\/value>/m, 1]
      expect(level).to eq('0')
    end

    it 'leaves an unmuted clip at unity with no audio filter' do
      xml = described_class.new([{ path: clip_a_path }]).to_xml
      clipitem = xml[/<clipitem id="clipitem-audio-1">.*?<\/clipitem>/m]

      expect(clipitem).not_to include('audiolevels')
    end

    # video_enabled/audio_enabled let a stacked alternate take sit on the
    # timeline without rendering — each flag disables only its own clipitem.
    it 'disables only the video clipitem for a clip with video_enabled: false' do
      xml = described_class.new([{ path: clip_a_path, video_enabled: false }]).to_xml
      video = xml[/<clipitem id="clipitem-video-1">.*?<\/clipitem>/m]
      audio = xml[/<clipitem id="clipitem-audio-1">.*?<\/clipitem>/m]

      expect(video).to include('<enabled>FALSE</enabled>')
      expect(audio).to include('<enabled>TRUE</enabled>')
    end

    it 'disables only the audio clipitem for a clip with audio_enabled: false' do
      xml = described_class.new([{ path: clip_a_path, audio_enabled: false }]).to_xml
      video = xml[/<clipitem id="clipitem-video-1">.*?<\/clipitem>/m]
      audio = xml[/<clipitem id="clipitem-audio-1">.*?<\/clipitem>/m]

      expect(video).to include('<enabled>TRUE</enabled>')
      expect(audio).to include('<enabled>FALSE</enabled>')
    end

    it 'writes both clipitems enabled when neither flag is given' do
      xml = described_class.new([{ path: clip_a_path }]).to_xml
      video = xml[/<clipitem id="clipitem-video-1">.*?<\/clipitem>/m]
      audio = xml[/<clipitem id="clipitem-audio-1">.*?<\/clipitem>/m]

      expect(video).to include('<enabled>TRUE</enabled>')
      expect(audio).to include('<enabled>TRUE</enabled>')
    end
  end

  # ButterCut report 21: multi-mono footage with an empty channel 1 and the
  # real sound on 2 and 3 exported a timeline with no sound at all.
  describe 'source audio track' do
    let(:media_dir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(media_dir) }

    # A real file, so the level check runs against real ffmpeg: one mono
    # stream per source, silent where `tracks` says :silent.
    def multi_mono(name, tracks)
      path = File.join(media_dir, name)
      sources = tracks.map { |kind| kind == :silent ? 'anullsrc=r=48000:cl=mono' : 'sine=f=440:r=48000' }
      inputs = ['-f', 'lavfi', '-i', 'color=c=black:s=64x64:r=25'] + sources.flat_map { |src| ['-f', 'lavfi', '-i', src] }
      maps = (0..sources.size).flat_map { |i| ['-map', i.to_s] }
      _, status = Open3.capture2e(MediaTools.ffmpeg, '-y', *inputs, *maps, '-t', '1', '-c:v', 'mjpeg', '-c:a', 'pcm_s16le', path)
      raise "couldn't build #{name}" unless status.success?

      metadata_by_path[path] = JSON.parse(Open3.capture2(MediaTools.ffprobe, '-v', 'quiet', '-print_format', 'json',
                                                         '-show_format', '-show_streams', path).first)
      path
    end

    def audio_trackindex(path)
      xml = described_class.new([{ path: path }]).to_xml
      xml[/<clipitem id="clipitem-audio-1">.*?<sourcetrack>.*?<trackindex>(\d+)<\/trackindex>/m, 1].to_i
    end

    it 'points the audio at the first source track with sound when track 1 is silent' do
      expect(audio_trackindex(multi_mono('silent_first.mov', %i[silent tone tone]))).to eq(2)
    end

    it 'keeps track 1 when it has sound' do
      expect(audio_trackindex(multi_mono('tone_first.mov', %i[tone silent tone]))).to eq(1)
    end

    it 'falls back to track 1 when every track is silent' do
      expect(audio_trackindex(multi_mono('all_silent.mov', %i[silent silent]))).to eq(1)
    end

    it 'skips the level check for a single-track source' do
      generator = described_class.new([{ path: clip_a_path }])
      expect(generator).not_to receive(:audible_track?)

      expect(generator.to_xml).to match(%r{<mediatype>audio</mediatype>\s*<trackindex>1</trackindex>})
    end
  end

  # NTSC fractional rates (29.97/23.976) are what most real camera footage
  # shoots, and the 1001-denominator math is where xmeml frame drift hides:
  # the timebase must round to a whole number, <ntsc> must flag the fraction,
  # and drop-frame timecode must subtract the dropped frame numbers.
  describe 'NTSC fractional-rate sequences' do
    require 'nokogiri'

    let(:df_a_path) { '/tmp/fcp7_ntsc_a.mov' } # 29.97 DF, 1-hour source timecode
    let(:df_b_path) { '/tmp/fcp7_ntsc_b.mov' } # 29.97, no timecode
    let(:ndf_path)  { '/tmp/fcp7_ntsc_23976.mov' } # 23.976 NDF
    let(:pal_path)  { '/tmp/fcp7_pal.mov' } # 25 fps, integer rate

    let(:ntsc_metadata_by_path) do
      {
        df_a_path => build_metadata(duration_seconds: 4.0, frame_rate: '30000/1001', timecode: '01:00:00;00'),
        df_b_path => build_metadata(duration_seconds: 2.0, frame_rate: '30000/1001'),
        ndf_path => build_metadata(duration_seconds: 4.0, frame_rate: '24000/1001', timecode: '01:00:00:00'),
        pal_path => build_metadata(duration_seconds: 2.0, frame_rate: '25/1')
      }
    end

    before do
      allow_any_instance_of(described_class).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
        ntsc_metadata_by_path.fetch(path)
      end
    end

    context 'with a 29.97 drop-frame sequence' do
      let(:doc) do
        Nokogiri::XML(described_class.new([
          { path: df_a_path },
          { path: df_b_path, start_at: 1.0, duration: 1.0 }
        ]).to_xml)
      end

      it 'rounds the sequence timebase to 30 and flags NTSC' do
        rate = doc.at_xpath('/xmeml/sequence/rate')
        expect(rate.at_xpath('timebase').text).to eq('30')
        expect(rate.at_xpath('ntsc').text).to eq('TRUE')
      end

      it 'marks the sequence timecode drop-frame' do
        timecode = doc.at_xpath('/xmeml/sequence/timecode')
        expect(timecode.at_xpath('displayformat').text).to eq('DF')
        expect(timecode.at_xpath('frame').text).to eq('0')
      end

      it 'converts whole-second trims into 29.97 frame counts' do
        # clip_a full 4.0s → 119.88 exact frames, rounded to 120.
        first = doc.at_xpath('//clipitem[@id="clipitem-video-1"]')
        expect(first.at_xpath('start').text).to eq('0')
        expect(first.at_xpath('end').text).to eq('120')

        # clip_b: 1.0s in-point → 30 frames, 1.0s duration → 30 frames.
        second = doc.at_xpath('//clipitem[@id="clipitem-video-2"]')
        expect(second.at_xpath('start').text).to eq('120')
        expect(second.at_xpath('end').text).to eq('150')
        expect(second.at_xpath('in').text).to eq('30')
        expect(second.at_xpath('out').text).to eq('60')

        expect(doc.at_xpath('/xmeml/sequence/duration').text).to eq('150')
      end

      it 'writes the drop-frame source timecode as a dropped frame count' do
        # 01:00:00;00 DF: 108000 nominal frames minus 2 × (60 − 6) dropped = 107892.
        file_timecode = doc.at_xpath('//clipitem[@id="clipitem-video-1"]/file/timecode')
        expect(file_timecode.at_xpath('frame').text).to eq('107892')
        expect(file_timecode.at_xpath('displayformat').text).to eq('DF')
      end
    end

    context 'with a 23.976 non-drop sequence' do
      let(:doc) { Nokogiri::XML(described_class.new([{ path: ndf_path }]).to_xml) }

      it 'rounds the timebase to 24, flags NTSC, and stays non-drop' do
        rate = doc.at_xpath('/xmeml/sequence/rate')
        expect(rate.at_xpath('timebase').text).to eq('24')
        expect(rate.at_xpath('ntsc').text).to eq('TRUE')
        expect(doc.at_xpath('/xmeml/sequence/timecode/displayformat').text).to eq('NDF')
      end

      it 'counts source timecode frames at the nominal rate' do
        # 01:00:00:00 NDF at nominal 24 → 86400 frames; 4.0s → 96 frames.
        file_timecode = doc.at_xpath('//clipitem[@id="clipitem-video-1"]/file/timecode')
        expect(file_timecode.at_xpath('frame').text).to eq('86400')
        expect(doc.at_xpath('/xmeml/sequence/duration').text).to eq('96')
      end
    end

    context 'with a PAL asset cut into a 29.97 sequence' do
      let(:doc) do
        Nokogiri::XML(described_class.new([
          { path: df_a_path },
          { path: pal_path }
        ]).to_xml)
      end

      it 'keeps the sequence NTSC while the PAL file keeps its own integer rate' do
        sequence_rate = doc.at_xpath('/xmeml/sequence/rate')
        expect(sequence_rate.at_xpath('timebase').text).to eq('30')
        expect(sequence_rate.at_xpath('ntsc').text).to eq('TRUE')

        pal_file_rate = doc.at_xpath('//clipitem[@id="clipitem-video-2"]/file/rate')
        expect(pal_file_rate.at_xpath('timebase').text).to eq('25')
        expect(pal_file_rate.at_xpath('ntsc').text).to eq('FALSE')
      end

      it 'declares each clipitem rate as the source timebase (conform metadata)' do
        %w[clipitem-video-2 clipitem-audio-2].each do |id|
          rate = doc.at_xpath("//clipitem[@id='#{id}']/rate")
          expect(rate.at_xpath('timebase').text).to eq('25')
          expect(rate.at_xpath('ntsc').text).to eq('FALSE')
        end
      end

      it 'writes in/out on the sequence frame grid, like start/end' do
        # Premiere and Resolve decode clipitem in/out as source seconds ×
        # SEQUENCE rate regardless of the declared clipitem/file rate —
        # verified frame-by-frame in both editors (editor round-trip QA,
        # mixed-rate-pal25). The 2.0s PAL clip therefore spans 60 grid units
        # (29.97), not its 50 native frames; only the file-level <duration>
        # and <timecode> stay in media frames.
        pal_clip = doc.at_xpath('//clipitem[@id="clipitem-video-2"]')
        expect(pal_clip.at_xpath('in').text).to eq('0')
        expect(pal_clip.at_xpath('out').text).to eq('60')
        expect(pal_clip.at_xpath('start').text).to eq('120')
        expect(pal_clip.at_xpath('end').text).to eq('180')
        expect(pal_clip.at_xpath('file/duration').text).to eq('50')

        expect(doc.at_xpath('/xmeml/sequence/duration').text).to eq('180')
      end
    end
  end
end
