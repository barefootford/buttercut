require 'spec_helper'
require 'nokogiri'

# Audio and still-image clips ride the single timeline track alongside video.
# These specs feed the generators synthetic ffprobe metadata (no real audio/
# image fixtures needed) and assert each kind emits the right timeline element.
RSpec.describe 'Audio and image clips (single-track media types)' do
  let(:video_path) { '/tmp/mt_video.mov' }
  let(:audio_path) { '/tmp/mt_song.mp3' }
  let(:image_path) { '/tmp/mt_photo.jpg' }

  def video_metadata(width: 1920, height: 1080, frame_rate: '30/1', sample_rate: '48000', duration: 6.0)
    {
      'streams' => [
        { 'codec_type' => 'video', 'width' => width, 'height' => height, 'r_frame_rate' => frame_rate },
        { 'codec_type' => 'audio', 'sample_rate' => sample_rate }
      ],
      'format' => { 'duration' => duration.to_s, 'tags' => {} }
    }
  end

  def audio_metadata(sample_rate: '44100', duration: 30.0)
    {
      'streams' => [{ 'codec_type' => 'audio', 'sample_rate' => sample_rate }],
      'format' => { 'duration' => duration.to_s, 'tags' => {} }
    }
  end

  # ffprobe reports a still as a single-frame video stream, no audio, no duration.
  # The degenerate "0/0" frame rate is the realistic worst case.
  def image_metadata(width: 1080, height: 1350, frame_rate: '0/0')
    {
      'streams' => [{ 'codec_type' => 'video', 'width' => width, 'height' => height, 'r_frame_rate' => frame_rate }],
      'format' => { 'tags' => {} }
    }
  end

  let(:metadata_by_path) do
    { video_path => video_metadata, audio_path => audio_metadata, image_path => image_metadata }
  end

  before do
    # extract_metadata_from_ffprobe lives on EditorBase, so one stub on the base
    # covers every generator (FCPX, FCP7, Premiere, Resolve) without the
    # parent/subclass any_instance conflict that stubbing each class separately hits.
    allow_any_instance_of(ButterCut::EditorBase)
      .to receive(:extract_metadata_from_ffprobe) { |_i, path| metadata_by_path.fetch(path) }
  end

  describe 'EditorBase stream accessors degrade instead of crashing' do
    let(:gen) { ButterCut::FCPX.new([{ path: video_path, media_type: 'video' }, { path: audio_path, media_type: 'audio' }, { path: image_path, media_type: 'image' }]) }

    it 'falls back to defaults for an audio-only clip (no video stream)' do
      expect(gen.video_width(audio_path)).to eq(ButterCut::EditorBase::DEFAULT_WIDTH)
      expect(gen.video_height(audio_path)).to eq(ButterCut::EditorBase::DEFAULT_HEIGHT)
      expect(gen.frame_rate(audio_path)).to eq(ButterCut::EditorBase::DEFAULT_FRAME_RATE)
      expect(gen.video_rotation(audio_path)).to eq(0)
      expect(gen.audio_sample_rate(audio_path)).to eq('44100') # the real audio rate is still read
      expect { gen.frame_duration(audio_path) }.not_to raise_error
    end

    it 'falls back to a default sample rate and a finite frame duration for an image' do
      expect(gen.audio_sample_rate(image_path)).to eq(ButterCut::EditorBase::DEFAULT_SAMPLE_RATE)
      # "0/0" must not become "1/0s" (which divides by zero downstream).
      expect(gen.frame_duration(image_path)).to eq('1/30s')
      expect { gen.round_to_frame_boundary(2.0, gen.frame_duration(image_path)) }.not_to raise_error
    end

    it 'reads clip kind from the media_type the exporter threads in' do
      expect(gen.clip_kind({ path: video_path, media_type: 'video' })).to eq('video')
      expect(gen.clip_kind({ path: audio_path, media_type: 'audio' })).to eq('audio')
      expect(gen.clip_kind({ path: image_path, media_type: 'image' })).to eq('image')
    end

    it 'derives the sequence format from the first video clip, not an audio/image lead' do
      gen2 = ButterCut::FCPX.new([
                                   { path: audio_path, media_type: 'audio' },
                                   { path: video_path, media_type: 'video' },
                                   { path: image_path, media_type: 'image' }
                                 ])
      expect(gen2.format_width).to eq(1920)
      expect(gen2.format_height).to eq(1080)
    end
  end

  describe 'FCP7 mixed timeline' do
    let(:clips) do
      [
        { path: video_path, media_type: 'video' },
        { path: audio_path, media_type: 'audio', start_at: 0.0, duration: 4.0 },
        { path: image_path, media_type: 'image', duration: 5.0 }
      ]
    end
    let(:doc) { Nokogiri::XML(ButterCut::FCP7.new(clips).to_xml) }

    it 'puts video + image clipitems on the video track (audio excluded)' do
      names = doc.xpath('/xmeml/sequence/media/video/track/clipitem/name').map(&:text)
      expect(names).to eq(%w[mt_video mt_photo])
    end

    it 'puts video + audio clipitems on the audio track (image excluded)' do
      names = doc.xpath('/xmeml/sequence/media/audio/track/clipitem/name').map(&:text)
      expect(names).to eq(%w[mt_video mt_song])
    end

    it 'does not declare a phantom audio track on the image file element' do
      image_item = doc.xpath('/xmeml/sequence/media/video/track/clipitem')
                      .find { |c| c.at_xpath('name').text == 'mt_photo' }
      expect(image_item.xpath('file/media/audio')).to be_empty
      expect(image_item.xpath('file/media/video')).not_to be_empty
    end

    it 'only links the clip that has both video and audio' do
      links = doc.xpath('//link/linkclipref').map(&:text).uniq
      expect(links).to contain_exactly('clipitem-video-1', 'clipitem-audio-1')
    end
  end

  describe 'FCPX mixed timeline' do
    let(:clips) do
      [
        { path: video_path, media_type: 'video' },
        { path: audio_path, media_type: 'audio', start_at: 0.0, duration: 4.0 },
        { path: image_path, media_type: 'image', duration: 5.0 }
      ]
    end
    let(:doc) { Nokogiri::XML(ButterCut::FCPX.new(clips).to_xml) }

    def asset_for(basename)
      doc.xpath('//resources/asset').find { |a| a['src'].include?(basename) }
    end

    def clip_for(filename)
      doc.xpath('//spine/asset-clip').find { |c| c['name'] == filename }
    end

    it 'marks the audio asset hasVideo=0, hasAudio=1' do
      a = asset_for('mt_song')
      expect(a['hasVideo']).to eq('0')
      expect(a['hasAudio']).to eq('1')
    end

    it 'marks the image asset hasVideo=1, hasAudio=0 and omits audioRate' do
      a = asset_for('mt_photo')
      expect(a['hasVideo']).to eq('1')
      expect(a['hasAudio']).to eq('0')
      expect(a['audioRate']).to be_nil
    end

    it 'drops audioRole/adjust-volume from the image clip but keeps them on audio' do
      image_clip = clip_for('mt_photo.jpg')
      expect(image_clip['audioRole']).to be_nil
      expect(image_clip.xpath('adjust-volume')).to be_empty

      audio_clip = clip_for('mt_song.mp3')
      expect(audio_clip['audioRole']).to eq('dialogue')
      expect(audio_clip.xpath('adjust-volume')).not_to be_empty
    end

    it 'emits one asset-clip per timeline clip' do
      expect(doc.xpath('//spine/asset-clip').size).to eq(3)
    end
  end

  describe 'Premiere with an audio clip in first position' do
    it 'does not crash on format dimensions and derives them from the video clip' do
      gen = ButterCut::Premiere.new([{ path: audio_path, media_type: 'audio' }, { path: video_path, media_type: 'video' }])
      expect { gen.to_xml }.not_to raise_error
      expect(gen.format_width).to eq(1920)
    end
  end
end
