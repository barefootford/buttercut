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

  # Stills have no audio stream and no source frame rate. The FCP7 writer must
  # drop the audio clipitem, the per-file <audio> characteristics, and the audio
  # link, and fall back to the 24fps default grid + default hold.
  describe 'still images' do
    let(:image_path) { '/tmp/fcp7_still.png' }

    before do
      allow_any_instance_of(described_class).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
        path == image_path ? image_metadata : metadata_by_path.fetch(path)
      end
    end

    let(:doc) { Nokogiri::XML(described_class.new([{ path: image_path }]).to_xml) }

    it 'emits a video clipitem but no audio clipitem' do
      expect(doc.xpath('//clipitem[starts-with(@id, "clipitem-video")]').length).to eq(1)
      expect(doc.xpath('//clipitem[starts-with(@id, "clipitem-audio")]').length).to eq(0)
    end

    it 'omits the per-file <audio> characteristics' do
      file_media = doc.at_xpath('//clipitem/file/media')
      expect(file_media.at_xpath('video')).not_to be_nil
      expect(file_media.at_xpath('audio')).to be_nil
    end

    it 'writes no dangling audio link' do
      xml = described_class.new([{ path: image_path }]).to_xml
      expect(xml).not_to include('<linkclipref>clipitem-audio')
    end

    it 'holds the still for the default duration (4s = 96 frames at the 24fps default)' do
      clip = doc.at_xpath('//clipitem[starts-with(@id, "clipitem-video")]')
      expect(clip.at_xpath('duration').text).to eq('96')
      expect(clip.at_xpath('in').text).to eq('0')
      expect(clip.at_xpath('out').text).to eq('96')
    end

    it 'still carries the image width/height' do
      expect(doc.at_xpath('//clipitem/file/media/video/samplecharacteristics/width').text).to eq('1920')
      expect(doc.at_xpath('//clipitem/file/media/video/samplecharacteristics/height').text).to eq('1080')
    end

    it 'gives a still its own video clipitem while a leading video keeps its audio clipitem' do
      mixed = Nokogiri::XML(described_class.new([{ path: clip_a_path }, { path: image_path }]).to_xml)
      expect(mixed.xpath('//clipitem[starts-with(@id, "clipitem-video")]').length).to eq(2)
      expect(mixed.xpath('//clipitem[starts-with(@id, "clipitem-audio")]').length).to eq(1)
    end

    # Regression: when a still precedes a video, the video's audio <link> must
    # reference its position in the AUDIO track (1 — the only audio clip), not its
    # video-track index (2). Using the video-track index pointed past the audio
    # track and dropped the A/V link on import in Premiere.
    it 'indexes a following video\'s audio link by audio-track position, not video-track position' do
      mixed = Nokogiri::XML(described_class.new([{ path: image_path }, { path: clip_a_path }]).to_xml)
      video_clip = mixed.at_xpath('//clipitem[@id="clipitem-video-2"]')
      video_link = video_clip.xpath('link').find { |l| l.at_xpath('mediatype').text == 'video' }
      audio_link = video_clip.xpath('link').find { |l| l.at_xpath('mediatype').text == 'audio' }

      expect(video_link.at_xpath('clipindex').text).to eq('2') # video track: still, then video
      expect(audio_link.at_xpath('clipindex').text).to eq('1') # audio track: just this video
    end
  end

  # A silent video (no audio stream) has a real frame rate/duration but no audio,
  # so it's handled like a still on the audio side: no audio clipitem, no per-file
  # <audio> characteristics, no audio link.
  describe 'silent video (no audio stream)' do
    let(:silent_path) { '/tmp/fcp7_silent.mov' }

    before do
      allow_any_instance_of(described_class).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
        path == silent_path ? silent_metadata(frame_rate: '25/1', duration: '4.0') : metadata_by_path.fetch(path)
      end
    end

    it 'emits a video clipitem but no audio clipitem, characteristics, or link' do
      doc = Nokogiri::XML(described_class.new([{ path: silent_path }]).to_xml)
      expect(doc.xpath('//clipitem[starts-with(@id, "clipitem-video")]').length).to eq(1)
      expect(doc.xpath('//clipitem[starts-with(@id, "clipitem-audio")]').length).to eq(0)
      expect(doc.at_xpath('//clipitem/file/media/audio')).to be_nil
      expect(doc.to_xml).not_to include('<linkclipref>clipitem-audio')
    end

    it 'keeps the audio link index correct for an audio clip that follows a silent video' do
      doc = Nokogiri::XML(described_class.new([{ path: silent_path }, { path: clip_a_path }]).to_xml)
      video_clip = doc.at_xpath('//clipitem[@id="clipitem-video-2"]')
      audio_link = video_clip.xpath('link').find { |l| l.at_xpath('mediatype').text == 'audio' }
      expect(audio_link.at_xpath('clipindex').text).to eq('1') # audio track skips the silent video
    end
  end
end
