# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

# Image (still) handling across all three generators. Stills are timeless: they
# carry only dimensions, take their duration from the cut, and produce no audio.
# The behaviors asserted here were verified by importing the exported XML into
# Final Cut Pro, Premiere, and DaVinci Resolve — these specs lock the structure
# the editors accepted so it can't silently regress.
RSpec.describe 'Generator still handling' do
  let(:video_path)  { '/tmp/stills_spec_video.mov' }
  let(:image_path)  { '/tmp/stills_spec_red.png' }
  let(:square_path) { '/tmp/stills_spec_square.png' }
  # A space + non-ASCII filename — the URL-encoding regression case.
  let(:unicode_image_path) { '/tmp/blue café (test).jpg' }

  def video_metadata(width: 1920, height: 1080, frame_rate: '24/1', duration: 4.0, sample_rate: '48000', timecode: nil)
    video_stream = {
      'codec_type' => 'video', 'codec_name' => 'h264',
      'width' => width, 'height' => height, 'r_frame_rate' => frame_rate,
      'color_space' => 'bt709', 'color_primaries' => 'bt709', 'color_transfer' => 'bt709'
    }
    video_stream['tags'] = { 'timecode' => timecode } if timecode
    {
      'streams' => [video_stream, { 'codec_type' => 'audio', 'sample_rate' => sample_rate }],
      'format' => { 'duration' => duration.to_s, 'tags' => timecode ? { 'timecode' => timecode } : {} }
    }
  end

  # An image probes as a single video stream with dimensions and NO audio stream
  # — exactly what ffprobe returns for a JPEG/PNG.
  def image_metadata(width:, height:)
    {
      'streams' => [{ 'codec_type' => 'video', 'codec_name' => 'png', 'width' => width, 'height' => height }],
      'format' => { 'duration' => 'N/A', 'tags' => {} }
    }
  end

  let(:metadata_by_path) do
    {
      video_path => video_metadata(timecode: '01:00:00:00'),
      image_path => image_metadata(width: 1920, height: 1080),
      square_path => image_metadata(width: 1080, height: 1080),
      unicode_image_path => image_metadata(width: 3840, height: 2160)
    }
  end

  before do
    allow_any_instance_of(ButterCut::EditorBase).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
      metadata_by_path.fetch(path)
    end
  end

  # An image-only cut on an explicit 24fps/1920x1080 timeline (what the cut skill
  # writes for image-only cuts) plus a video+stills mix.
  let(:image_only_clips) do
    [
      { path: image_path,  type: :image, duration: 3.0 },
      { path: square_path, type: :image, duration: 2.0 }
    ]
  end
  let(:timeline_block) { { frame_rate: 24, width: 1920, height: 1080 } }

  let(:mixed_clips) do
    [
      { path: video_path, type: :video, start_at: 0.0, duration: 2.0 },
      { path: image_path, type: :image, duration: 3.0 }
    ]
  end

  describe 'image clip validation (EditorBase)' do
    it 'rejects an image clip with no duration — stills are timeless' do
      clips = [{ path: image_path, type: :image }]
      expect { ButterCut::FCPX.new(clips, timeline: timeline_block) }
        .to raise_error(ArgumentError, /Image clip.*must have a 'duration'/)
    end

    it 'accepts an image clip once a duration is given' do
      clips = [{ path: image_path, type: :image, duration: 3.0 }]
      expect { ButterCut::FCPX.new(clips, timeline: timeline_block) }.not_to raise_error
    end
  end

  describe ButterCut::FCPX do
    it 'emits one rate-undefined format per unique still dimension, with no frameDuration' do
      xml = described_class.new(image_only_clips, timeline: timeline_block).to_xml
      # 1920x1080 and 1080x1080 → two distinct still formats.
      expect(xml).to include('<format id="r_still_1920x1080" name="FFVideoFormatRateUndefined" width="1920" height="1080"/>')
      expect(xml).to include('<format id="r_still_1080x1080" name="FFVideoFormatRateUndefined" width="1080" height="1080"/>')
      # The timeless marker is the ABSENCE of frameDuration on the still format.
      expect(xml).not_to match(/name="FFVideoFormatRateUndefined"[^>]*frameDuration/)
    end

    it 'makes still assets timeless (duration 0s, video-only, no audio attributes)' do
      xml = described_class.new(image_only_clips, timeline: timeline_block).to_xml
      asset = xml[/<asset [^>]*name="stills_spec_red\.png"[^>]*\/>/]
      expect(asset).to include('start="0s"', 'duration="0s"', 'hasVideo="1"')
      expect(asset).not_to include('hasAudio')
      expect(asset).not_to include('audioRate')
    end

    it 'places stills on the spine as <video> elements (never asset-clip) with the cut duration' do
      xml = described_class.new(image_only_clips, timeline: timeline_block).to_xml
      expect(xml).to match(/<video name="stills_spec_red\.png"[^>]*offset="0s"[^>]*duration="3\/1s"/)
      expect(xml).to match(/<video name="stills_spec_square\.png"[^>]*offset="3\/1s"[^>]*duration="2\/1s"/)
      # A still must not be emitted as an asset-clip.
      expect(xml).not_to match(/<asset-clip[^>]*stills_spec_red/)
    end

    it 'mixes a video asset-clip and a still <video> in one spine' do
      xml = described_class.new(mixed_clips).to_xml
      expect(xml).to match(/<asset-clip name="stills_spec_video\.mov"/)
      expect(xml).to match(/<video name="stills_spec_red\.png"/)
    end

    it 'percent-encodes spaces and non-ASCII in the still asset src' do
      clips = [{ path: unicode_image_path, type: :image, duration: 3.0 }]
      xml = described_class.new(clips, timeline: timeline_block).to_xml
      expect(xml).to include('src="file:///tmp/blue%20caf%C3%A9%20%28test%29.jpg"')
    end

    it 'validates against the FCPXML 1.8 DTD' do
      skip 'xmllint not available' unless system('command -v xmllint > /dev/null 2>&1')
      dtd = File.expand_path('../../dtd/FCPXMLv1_8.dtd', __dir__)
      skip 'DTD not present' unless File.exist?(dtd)

      xml = described_class.new(mixed_clips).to_xml
      Tempfile.create(['stills', '.fcpxml']) do |f|
        f.write(xml)
        f.flush
        expect(system('xmllint', '--noout', '--dtdvalid', dtd, f.path, out: File::NULL, err: File::NULL))
          .to be(true)
      end
    end
  end

  shared_examples 'an xmeml still generator' do
    it 'marks the still clipitem with <stillframe>TRUE</stillframe>' do
      xml = described_class.new(image_only_clips, timeline: timeline_block).to_xml
      expect(xml.scan('<stillframe>TRUE</stillframe>').size).to eq(2)
    end

    it 'gives the still a file duration equal to the timeline duration, at the sequence rate' do
      xml = described_class.new(image_only_clips, timeline: timeline_block).to_xml
      clipitem = xml[/<clipitem id="clipitem-video-1">.*?<\/clipitem>/m]
      # 3.0s at 24fps → 72 frames, in/out/duration all span the timeline.
      expect(clipitem).to include('<duration>72</duration>', '<in>0</in>', '<out>72</out>')
      # Still adopts the sequence timebase (24), not a native still rate.
      expect(clipitem).to include('<timebase>24</timebase>')
    end

    it 'gives the still no source timecode block and no audio (no audio clipitem, no links)' do
      xml = described_class.new(image_only_clips, timeline: timeline_block).to_xml
      clipitem = xml[/<clipitem id="clipitem-video-1">.*?<\/clipitem>/m]
      expect(clipitem).not_to include('<timecode>')
      expect(clipitem).not_to include('mediatype>audio')
      # Pure-still timeline: no audio clipitems, no link entries at all.
      expect(xml).not_to include('clipitem-audio')
      expect(xml).not_to include('<link>')
    end

    it 'keeps audio + links for video clips while the still has neither' do
      xml = described_class.new(mixed_clips).to_xml
      # The video clip gets its audio clipitem and link pair...
      expect(xml).to include('clipitem-audio')
      expect(xml).to include('<link>')
      # ...but only ONE stillframe marker and no audio clipitem for the still.
      expect(xml.scan('<stillframe>TRUE</stillframe>').size).to eq(1)
      # Exactly one audio clipitem (the video's), not two.
      expect(xml.scan(/<clipitem id="clipitem-audio-\d+">/).size).to eq(1)
    end

    it 'percent-encodes spaces and non-ASCII in the still pathurl' do
      clips = [{ path: unicode_image_path, type: :image, duration: 3.0 }]
      xml = described_class.new(clips, timeline: timeline_block).to_xml
      expect(xml).to include('<pathurl>file:///tmp/blue%20caf%C3%A9%20%28test%29.jpg</pathurl>')
    end
  end

  describe ButterCut::FCP7 do
    it_behaves_like 'an xmeml still generator'
  end

  describe ButterCut::Resolve do
    it_behaves_like 'an xmeml still generator'
  end

  describe ButterCut::Premiere do
    it_behaves_like 'an xmeml still generator'

    it 'adds no rotation filter for a still (images carry no rotation flag)' do
      clips = [{ path: image_path, type: :image, duration: 3.0 }]
      xml = described_class.new(clips, timeline: timeline_block).to_xml
      expect(xml).not_to include('<filter>')
      expect(xml).not_to include('Basic Motion')
    end
  end
end
