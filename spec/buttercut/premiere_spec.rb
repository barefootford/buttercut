require 'spec_helper'

# Premiere forks the FCP7 XML so it can write rotation explicitly into the timeline.
#
# Background: vertical footage is commonly stored as a LANDSCAPE frame (e.g. 3840x2160)
# with a display-matrix rotation flag of -90. Final Cut and DaVinci Resolve read that
# flag from the source file on import and auto-correct, so the clip shows upright.
# Adobe Premiere Pro ignores the source flag and trusts only what the XML declares —
# so the shared FCP7 output (raw landscape dimensions, no rotation) imports SIDEWAYS.
#
# These specs are the failing-first contract for the fix: the Premiere generator must
# emit the rotation into the XML, and the Resolve (FCP7) path must stay untouched.
RSpec.describe ButterCut::Premiere do
  let(:rotated_clip_path)   { '/tmp/premiere_rotated.mov' }
  let(:upright_clip_path)   { '/tmp/premiere_upright.mov' }

  # `rotation` mirrors ffprobe's modern display-matrix side data: a value of -90 means
  # the picture must be rotated to display upright (vertical footage in a landscape frame).
  def build_metadata(duration_seconds:, frame_rate: '30/1', width: 1920, height: 1080,
                     sample_rate: '48000', rotation: nil)
    video_stream = {
      'codec_type'  => 'video',
      'width'       => width,
      'height'      => height,
      'r_frame_rate' => frame_rate,
      'color_space' => 'bt709'
    }
    if rotation
      video_stream['side_data_list'] = [{ 'side_data_type' => 'Display Matrix', 'rotation' => rotation }]
    end

    audio_stream = { 'codec_type' => 'audio', 'sample_rate' => sample_rate }

    {
      'streams' => [video_stream, audio_stream],
      'format'  => { 'duration' => duration_seconds.to_s, 'tags' => {} }
    }
  end

  let(:cw_rotated_clip_path) { '/tmp/premiere_cw_rotated.mov' }

  let(:metadata_by_path) do
    {
      # Vertical footage stored landscape with a -90 rotation flag.
      rotated_clip_path => build_metadata(duration_seconds: 4.0, width: 3840, height: 2160, rotation: -90),
      # Ordinary landscape footage, no rotation.
      upright_clip_path => build_metadata(duration_seconds: 3.0, width: 1920, height: 1080),
      # Vertical footage rotated the other quarter-turn: a +90 display-matrix flag
      # normalizes to 270 clockwise, which the timeline writes the short way as -90.
      cw_rotated_clip_path => build_metadata(duration_seconds: 4.0, width: 3840, height: 2160, rotation: 90)
    }
  end

  before do
    allow_any_instance_of(ButterCut::EditorBase).to receive(:extract_metadata_from_ffprobe) do |_instance, path|
      metadata_by_path.fetch(path)
    end
  end

  describe '#to_xml' do
    it 'writes a Basic Motion rotation filter for a rotated source clip' do
      xml = described_class.new([{ path: rotated_clip_path }]).to_xml

      expect(xml).to include('<name>Basic Motion</name>')
      # A -90 display-matrix source must turn +90 clockwise to display upright.
      expect(xml).to match(%r{<parameterid>rotation</parameterid>.*?<value>90</value>}m)
    end

    it 'does not add a rotation filter to footage that is already upright' do
      xml = described_class.new([{ path: upright_clip_path }]).to_xml

      expect(xml).not_to include('<parameterid>rotation</parameterid>')
    end

    it 'writes the rotation the short way around for a 270-degree source' do
      xml = described_class.new([{ path: cw_rotated_clip_path }]).to_xml

      expect(xml).to match(%r{<parameterid>rotation</parameterid>.*?<value>-90</value>}m)
    end

    # The sequence frame follows the first clip's *display* orientation, so a
    # quarter-turn source must yield a portrait timeline (stored 3840x2160 swapped
    # to 2160x3840) rather than a landscape one the rotated footage can't fill.
    it 'swaps the sequence dimensions to portrait for quarter-turn footage' do
      xml = described_class.new([{ path: rotated_clip_path }]).to_xml
      format = xml[%r{<format>.*?</format>}m]

      expect(format).to include('<width>2160</width>')
      expect(format).to include('<height>3840</height>')
    end

    it 'leaves the sequence dimensions landscape for upright footage' do
      xml = described_class.new([{ path: upright_clip_path }]).to_xml
      format = xml[%r{<format>.*?</format>}m]

      expect(format).to include('<width>1920</width>')
      expect(format).to include('<height>1080</height>')
    end
  end

  # Real cuts mix orientations — a single timeline can hold rotated and upright clips
  # in any order. Rotation is per-clip, so each video clipitem must be judged on its own
  # source flag; the sequence frame, by contrast, follows only the FIRST clip.
  describe 'a timeline mixing rotated and upright clips' do
    let(:xml) do
      described_class.new([
        { path: rotated_clip_path },    # -90 source -> +90 cw
        { path: upright_clip_path },    # no rotation
        { path: cw_rotated_clip_path }  # +90 source -> 270, written the short way as -90
      ]).to_xml
    end
    let(:doc) { Nokogiri::XML(xml) }
    # Only the sequence's video track carries clipitems with filters; audio clipitems
    # (under media/audio) and the per-file <media><video> blocks have no <track>.
    let(:video_clipitems) { doc.xpath('/xmeml/sequence/media/video/track/clipitem') }
    let(:clipitem_by_name) do
      video_clipitems.each_with_object({}) { |ci, h| h[ci.at_xpath('name').text] = ci }
    end

    def baked_rotation(clipitem)
      clipitem.at_xpath(".//filter/effect[name='Basic Motion']/parameter[parameterid='rotation']/value")&.text
    end

    it 'judges each clip on its own source flag' do
      expect(video_clipitems.length).to eq(3)
      expect(baked_rotation(clipitem_by_name['premiere_rotated'])).to eq('90')
      expect(baked_rotation(clipitem_by_name['premiere_upright'])).to be_nil
      expect(baked_rotation(clipitem_by_name['premiere_cw_rotated'])).to eq('-90')
    end

    it 'writes exactly one Basic Motion filter per rotated clip' do
      expect(xml.scan('<name>Basic Motion</name>').length).to eq(2)
    end

    it 'orients the sequence to the first clip regardless of later clips' do
      format = xml[%r{<format>.*?</format>}m]

      expect(format).to include('<width>2160</width>')
      expect(format).to include('<height>3840</height>')
    end
  end

  # Regression guard: the Resolve path must NOT change — it already imports correctly
  # because Resolve reads the source rotation flag itself. If a future change starts
  # injecting rotation into the shared FCP7 output, this fails and warns us we have
  # double-rotated Resolve.
  describe 'Resolve output is left unchanged' do
    it 'emits no rotation filter for the same rotated clip' do
      xml = ButterCut::Resolve.new([{ path: rotated_clip_path }]).to_xml

      expect(xml).not_to include('<parameterid>rotation</parameterid>')
      expect(xml).not_to include('<name>Basic Motion</name>')
    end
  end
end
