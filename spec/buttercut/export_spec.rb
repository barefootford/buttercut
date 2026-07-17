# frozen_string_literal: true

require 'spec_helper'
require 'nokogiri'
require 'tempfile'
require_relative '../../lib/buttercut/export'

# End-to-end coverage of the Export entrypoint the cut skill shells out to:
# cut YAML + library.yaml → editor XML. Runs real ffprobe over the small
# committed fixture clips (23.976 fps, 1280x720, 48 kHz, no embedded timecode),
# so the numbers below are real frame math: at 23.976 a 2.0s trim rounds to
# 48 frames (1001/500s) and a 1.0s in-point to 24 frames (1001/1000s).
RSpec.describe Export do
  let(:clip_a) { fixture_media('MVI_0309_720p.mov') } # 4.202s
  let(:clip_b) { fixture_media('MVI_0323_720p.mov') } # 6.044s

  def perform(cut_path, out_path, editor: 'fcpx')
    silence_stdout do
      described_class.perform(roughcut_path: cut_path, output_path: out_path, editor: editor)
    end
  end

  def parse(path) = Nokogiri::XML(File.read(path))

  # A real PNG for image-clip examples, generated once — nothing large enters git.
  before(:context) do
    @stills_dir = Dir.mktmpdir('export-spec-stills')
    @still_path = File.join(@stills_dir, 'title card.png')
    ok = system(MediaTools.ffmpeg, '-y', '-f', 'lavfi', '-i', 'color=c=red:size=320x180',
                '-frames:v', '1', @still_path, out: File::NULL, err: File::NULL)
    raise "Could not generate still fixture with ffmpeg" unless ok && File.exist?(@still_path)
  end

  after(:context) { FileUtils.remove_entry(@stills_dir) }

  describe 'argument validation' do
    it 'requires roughcut_path, output_path, and editor' do
      expect { described_class.new(roughcut_path: nil, output_path: 'o.xml', editor: 'fcpx') }
        .to raise_error(ArgumentError, /roughcut_path/)
      expect { described_class.new(roughcut_path: 'c.yaml', output_path: '', editor: 'fcpx') }
        .to raise_error(ArgumentError, /output_path/)
      expect { described_class.new(roughcut_path: 'c.yaml', output_path: 'o.xml', editor: nil) }
        .to raise_error(ArgumentError, /editor/)
    end

    it 'rejects an unknown editor by name' do
      expect { described_class.new(roughcut_path: 'c.yaml', output_path: 'o.xml', editor: 'avid') }
        .to raise_error(ArgumentError, /Unknown editor 'avid'/)
    end

    it 'accepts editor names case-insensitively' do
      expect { described_class.new(roughcut_path: 'c.yaml', output_path: 'o.xml', editor: 'FCPX') }
        .not_to raise_error
    end
  end

  describe 'input errors' do
    it 'raises when the rough cut file does not exist' do
      cut = { 'clips' => [] }
      within_export_sandbox(cut: cut, media: [clip_a]) do |_cut_path, out|
        expect { perform('libraries/export-sandbox/cuts/nope.yaml', out) }
          .to raise_error(/Rough cut file not found/)
      end
    end

    it 'raises when the cut path is not inside libraries/<name>/cuts' do
      Dir.mktmpdir do |dir|
        stray = File.join(dir, 'cut.yaml')
        File.write(stray, { 'clips' => [] }.to_yaml)
        expect { perform(stray, File.join(dir, 'out.xml')) }
          .to raise_error(/Could not extract library name/)
      end
    end

    it 'raises when the library.yaml is missing' do
      cut = { 'clips' => [] }
      within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
        File.delete('libraries/export-sandbox/library.yaml')
        expect { perform(cut_path, out) }.to raise_error(/Library file not found/)
      end
    end
  end

  describe 'clip building' do
    it 'maps in/out points to source trim and timeline duration' do
      cut = { 'clips' => [
        { 'source_file' => 'MVI_0309_720p.mov', 'in_point' => '00:00:00', 'out_point' => '00:00:02' },
        { 'source_file' => 'MVI_0323_720p.mov', 'in_point' => '00:00:01', 'out_point' => '00:00:03' }
      ] }
      within_export_sandbox(cut: cut, media: [clip_a, clip_b]) do |cut_path, out|
        perform(cut_path, out)
        clips = parse(out).xpath('//spine/asset-clip')

        expect(clips.length).to eq(2)
        expect(clips[0]['duration']).to eq('1001/500s')  # 2.0s → 48 frames
        expect(clips[1]['offset']).to eq('1001/500s')    # placed right after clip 1
        expect(clips[1]['start']).to eq('1001/1000s')    # 1.0s in-point → 24 frames
        expect(clips[1]['duration']).to eq('1001/500s')
      end
    end

    it 'accepts bare numeric and decimal-second in/out points' do
      cut = { 'clips' => [
        { 'source_file' => 'MVI_0323_720p.mov', 'in_point' => '00:00:01.5', 'out_point' => 4 }
      ] }
      within_export_sandbox(cut: cut, media: [clip_b]) do |cut_path, out|
        perform(cut_path, out)
        clip = parse(out).at_xpath('//spine/asset-clip')

        expect(clip['start']).to eq('3003/2000s')   # 1.5s → 36 frames
        expect(clip['duration']).to eq('1001/400s') # 2.5s → 60 frames
      end
    end

    it 'passes mute through so the clip is silenced outright' do
      cut = { 'clips' => [
        { 'source_file' => 'MVI_0309_720p.mov', 'in_point' => 0, 'out_point' => 2, 'mute' => true }
      ] }
      within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
        perform(cut_path, out)
        volume = parse(out).at_xpath('//spine/asset-clip/adjust-volume')

        expect(volume['amount']).to eq('-96')
      end
    end

    it 'skips a clip whose source_file is not in the library, with a warning' do
      cut = { 'clips' => [
        { 'source_file' => 'MVI_0309_720p.mov', 'in_point' => 0, 'out_point' => 2 },
        { 'source_file' => 'not_in_library.mov', 'in_point' => 0, 'out_point' => 2 }
      ] }
      within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
        stderr = capture_stderr { perform(cut_path, out) }

        expect(stderr).to include('not_in_library.mov')
        expect(parse(out).xpath('//spine/asset-clip').length).to eq(1)
      end
    end

    it 'warns about an unsupported extension and exports it as video anyway' do
      Dir.mktmpdir do |dir|
        mkv = File.join(dir, 'legacy_clip.mkv')
        FileUtils.cp(clip_a, mkv) # .mov bytes — ffprobe reads the content fine
        cut = { 'clips' => [{ 'source_file' => 'legacy_clip.mkv', 'in_point' => 0, 'out_point' => 2 }] }
        within_export_sandbox(cut: cut, media: [mkv]) do |cut_path, out|
          stderr = capture_stderr { perform(cut_path, out) }

          expect(stderr).to include('outside the supported formats')
          expect(parse(out).xpath('//spine/asset-clip').length).to eq(1)
        end
      end
    end

    it 'requires a duration on image clips' do
      cut = { 'clips' => [{ 'source_file' => 'title card.png' }] }
      within_export_sandbox(cut: cut, media: [@still_path]) do |cut_path, out|
        expect { perform(cut_path, out) }
          .to raise_error(/missing a required 'duration:'/)
      end
    end

    it 'exports an image clip as a timeless still held for the cut duration' do
      cut = { 'clips' => [
        { 'source_file' => 'MVI_0309_720p.mov', 'in_point' => 0, 'out_point' => 2 },
        { 'source_file' => 'title card.png', 'duration' => 3 }
      ] }
      within_export_sandbox(cut: cut, media: [clip_a, @still_path]) do |cut_path, out|
        perform(cut_path, out)
        still = parse(out).at_xpath('//spine/video')

        expect(still['name']).to eq('title card.png')
        expect(still['duration']).to eq('3003/1000s') # 3.0s → 72 frames at 23.976
      end
    end
  end

  describe 'media pre-flight' do
    it 'exports cleanly when every source file is present' do
      cut = { 'clips' => [{ 'source_file' => 'MVI_0309_720p.mov', 'in_point' => 0, 'out_point' => 1 }] }
      within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
        expect { perform(cut_path, out) }.not_to raise_error
        expect(File.exist?(out)).to be(true)
      end
    end

    it 'fails fast (before ffprobe) when a single source file has moved' do
      cut = { 'clips' => [{ 'source_file' => 'C2407.MP4', 'in_point' => 0, 'out_point' => 2 }] }
      within_export_sandbox(cut: cut, media: ['/Volumes/ButterCut Spec Drive/CAC/C2407.MP4']) do |cut_path, out|
        expect { perform(cut_path, out) }
          .to raise_error(/1 of 1 source file isn't where the library expects/)
        expect(File.exist?(out)).to be(false)
      end
    end

    it 'groups several missing files under their shared volume and names verify_media' do
      cut = { 'clips' => [
        { 'source_file' => 'C2407.MP4', 'in_point' => 0, 'out_point' => 2 },
        { 'source_file' => 'C2408.MP4', 'in_point' => 0, 'out_point' => 2 }
      ] }
      media = ['/Volumes/ButterCut Spec Drive/CAC/C2407.MP4', '/Volumes/ButterCut Spec Drive/CAC/C2408.MP4']
      within_export_sandbox(cut: cut, media: media) do |cut_path, out|
        expect { perform(cut_path, out) }
          .to raise_error(/2 of 2 source files.*under \/Volumes\/ButterCut Spec Drive\/.*verify_media/m)
      end
    end
  end

  describe 'editor targets' do
    let(:cut) do
      { 'clips' => [{ 'source_file' => 'MVI_0309_720p.mov', 'in_point' => 0, 'out_point' => 2 }] }
    end

    it 'writes FCPXML 1.12 for resolve' do
      within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
        perform(cut_path, out, editor: 'resolve')
        doc = parse(out)

        expect(doc.at_xpath('/fcpxml')['version']).to eq('1.12')
        expect(doc.xpath('//spine/asset-clip').length).to eq(1)
      end
    end

    it 'writes xmeml for resolve_legacy, the temporary FCP7 fallback' do
      within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
        perform(cut_path, out, editor: 'resolve_legacy')
        xml = File.read(out)

        expect(xml).to include('<xmeml version="5">')
      end
    end

    it 'writes xmeml for premiere without rotating upright footage' do
      within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
        perform(cut_path, out, editor: 'premiere')
        xml = File.read(out)

        expect(xml).to include('<xmeml version="5">')
        expect(xml).not_to include('Basic Motion')
      end
    end

    it 'produces fcpx output that validates against the FCPXML 1.12 DTD' do
      skip 'xmllint not available' unless system('command -v xmllint > /dev/null 2>&1')
      dtd = File.expand_path('../../dtd/FCPXMLv1_12.dtd', __dir__)
      skip 'DTD not present' unless File.exist?(dtd)

      mixed = { 'clips' => [
        { 'source_file' => 'MVI_0309_720p.mov', 'in_point' => 0, 'out_point' => 2 },
        { 'source_file' => 'title card.png', 'duration' => 3 }
      ] }
      within_export_sandbox(cut: mixed, media: [clip_a, @still_path]) do |cut_path, out|
        perform(cut_path, out)

        expect(system('xmllint', '--noout', '--dtdvalid', dtd, out,
                      out: File::NULL, err: File::NULL)).to be(true)
      end
    end
  end

  describe 'timeline block' do
    it 'pins the output format from the cut YAML for an image-only cut' do
      cut = {
        'timeline' => { 'frame_rate' => 25, 'width' => 1920, 'height' => 1080 },
        'clips' => [{ 'source_file' => 'title card.png', 'duration' => 2 }]
      }
      within_export_sandbox(cut: cut, media: [@still_path]) do |cut_path, out|
        perform(cut_path, out)
        format = parse(out).at_xpath('//format[@id="r1"]')

        expect(format['frameDuration']).to eq('1/25s')
        expect(format['width']).to eq('1920')
        expect(format['height']).to eq('1080')
      end
    end
  end

  it 'returns the output path' do
    cut = { 'clips' => [{ 'source_file' => 'MVI_0309_720p.mov', 'in_point' => 0, 'out_point' => 1 }] }
    within_export_sandbox(cut: cut, media: [clip_a]) do |cut_path, out|
      expect(perform(cut_path, out)).to eq(out)
    end
  end
end
