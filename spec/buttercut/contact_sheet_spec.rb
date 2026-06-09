require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/buttercut/contact_sheet'

RSpec.describe ContactSheet, 'codec coverage', :fixtures do
  # Fixtures live in spec/assets/ (gitignored). The h264/hevc/prores clips are sliced
  # from real source footage. The four below are transcoded from those real clips —
  # regenerable from anywhere inside spec/assets/ with:
  #
  #   ffmpeg -y -i prores.mov -t 2 -c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p dnxhr.mov
  #
  #   ffmpeg -y -i h264_yuv422p10le_2s.mp4 -t 2 \
  #     -c:v libx265 -pix_fmt yuv422p10le -x265-params log-level=error \
  #     -tag:v hvc1 hevc_yuv422p10le.mov
  #
  #   ffmpeg -y -i prores.mov -t 2 -c:v mjpeg -pix_fmt yuvj420p -q:v 5 mjpeg.mov
  #
  #   ffmpeg -y -i h264_yuv420p.mp4 -t 2 -c:v libx264 -profile:v high -level 4.0 \
  #     -pix_fmt yuv420p -g 12 -keyint_min 12 -bf 2 -f mpegts avchd_mts.mts
  #
  # The tight GOP on avchd_mts.mts matters — without it, the skill's `-ss N -t 0.1` seek
  # window catches no keyframes and ffmpeg emits an empty output.
  CODEC_FIXTURES = {
    h264_yuv420p:          'h264_yuv420p.mp4',
    hevc_yuv420p10le:      'hevc_yuv420p10le.mov',
    h264_yuv422p10le:      'h264_yuv422p10le_2s.mp4',
    hevc_yuv422p10le:      'hevc_yuv422p10le.mov',
    hevc_portrait_rotated: 'hevc_portrait_rotated.mov',
    hevc_portrait_native:  'hevc_portrait_native.mov',
    h264_screen_vfr:       'h264_screen_vfr.mp4',
    avchd_mts:             'avchd_mts.mts',
    prores:                'prores.mov',
    dnxhr:                 'dnxhr.mov',
    mjpeg:                 'mjpeg.mov'
  }.freeze

  around do |example|
    Dir.mktmpdir('contact-sheet-spec-') do |dir|
      @tmp_dir = dir
      silence_stdout { example.run }
    end
  end

  define_method(:build_sheet) do |filename, label, **opts|
    ContactSheet.new(
      Fixtures.path(filename),
      nil, nil,
      library_dir: nil, output_path: File.join(@tmp_dir, "#{label}.jpg"), **opts
    )
  end

  def expect_valid_jpeg(path)
    expect(File.exist?(path)).to be(true), "expected JPEG at #{path}"
    expect(File.size(path)).to be > 0
    expect(File.binread(path, 3).bytes).to eq([0xFF, 0xD8, 0xFF])
  end

  CODEC_FIXTURES.each do |name, filename|
    context "with #{name}" do
      it 'produces a valid JPEG without raising' do
        expect_valid_jpeg(build_sheet(filename, name).extract)
      end
    end
  end

  describe 'dispatch behavior' do
    it 'routes heavy short clips to single-pass' do
      sheet = build_sheet('h264_yuv422p10le_2s.mp4', :heavy_short)
      sheet.extract
      expect(sheet.strategy).to eq(:single_pass)
    end

    it 'routes light clips to seek-and-grab with hwaccel on' do
      sheet = build_sheet('h264_yuv420p.mp4', :light)
      sheet.extract
      expect(sheet.strategy).to eq(:seek_and_grab)
      expect(sheet.hwaccel).to be(true)
    end

    it 'routes all-intra clips to seek-and-grab' do
      sheet = build_sheet('prores.mov', :all_intra)
      sheet.extract
      expect(sheet.strategy).to eq(:seek_and_grab)
    end

    it 'reads container rotation metadata from a real portrait iPhone clip' do
      sheet = build_sheet('hevc_portrait_rotated.mov', :rotated)
      sheet.extract
      expect(sheet.rotation).to eq(90)
    end

    # Some iPhone exports come out with portrait dimensions already baked into the stream
    # (height > width, no rotation tag). The scale filter `scale=W:-2` lets height float,
    # so the tiles end up taller than wide and the output grid is portrait-oriented.
    it 'produces a portrait-oriented grid for a natively vertical clip with no rotation tag' do
      sheet = build_sheet('hevc_portrait_native.mov', :portrait_native)
      output = sheet.extract
      expect(sheet.rotation).to eq(0)
      width, height = `#{Shellwords.escape(MediaTools.ffprobe)} -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 #{Shellwords.escape(output)}`.strip.split(',').map(&:to_i)
      expect(height).to be > width
    end

    # h264_screen_vfr.mp4 is regenerable via:
    #   ffmpeg -y -f lavfi -i "testsrc=size=640x360:rate=30:duration=4" \
    #     -vf "select='eq(n,0)+eq(n,1)+eq(n,30)+eq(n,60)+eq(n,90)+eq(n,119)'" \
    #     -fps_mode passthrough -c:v libx264 -pix_fmt yuv420p h264_screen_vfr.mp4
    # Sparse non-uniform `select` + `-fps_mode passthrough` keeps the source 30fps timestamps,
    # so r_frame_rate=30 but avg_frame_rate≈2 — a `setpts` filter would re-pack to CFR.
    it 'routes a real variable-frame-rate screen recording to seek-and-grab' do
      sheet = build_sheet('h264_screen_vfr.mp4', :vfr)
      sheet.extract
      expect(sheet.strategy).to eq(:seek_and_grab)
    end
  end
end

# Rotation comes from container metadata, and ffmpeg 7.1 won't synthesize that metadata
# on encode — so we exercise the parser directly. The two real-world formats are old
# MOV/MP4 `tags.rotate` (clockwise) and modern displaymatrix side_data (counter-clockwise).
RSpec.describe ContactSheet, '.extract_rotation' do
  it 'parses the legacy stream.tags.rotate field' do
    stream = { 'tags' => { 'rotate' => '90' } }
    expect(ContactSheet.extract_rotation(stream)).to eq(90)
  end

  it 'parses displaymatrix side_data and negates the sign' do
    stream = { 'side_data_list' => [{ 'side_data_type' => 'Display Matrix', 'rotation' => -90 }] }
    expect(ContactSheet.extract_rotation(stream)).to eq(90)
  end

  it 'normalizes 270 ccw to 90 cw equivalent' do
    stream = { 'side_data_list' => [{ 'rotation' => 270 }] }
    expect(ContactSheet.extract_rotation(stream)).to eq(90)
  end

  it 'returns 0 when no rotation metadata is present' do
    expect(ContactSheet.extract_rotation({})).to eq(0)
    expect(ContactSheet.extract_rotation('tags' => {})).to eq(0)
  end

  it 'prefers the rotate tag when both are present (older containers may carry both)' do
    stream = {
      'tags' => { 'rotate' => '180' },
      'side_data_list' => [{ 'rotation' => 0 }]
    }
    expect(ContactSheet.extract_rotation(stream)).to eq(180)
  end
end

# ffmpeg 7.1 normalizes muxer timestamps on output, so we can't reliably build a VFR
# fixture from a CFR lavfi source — ffprobe reads it back as CFR. Test the predicate
# against the raw fields it inspects.
RSpec.describe ContactSheet, '.compute_vfr' do
  it 'reports CFR when r_frame_rate and avg_frame_rate agree' do
    expect(ContactSheet.compute_vfr('30/1', '30/1')).to be(false)
  end

  it 'reports VFR when avg drops materially below r' do
    expect(ContactSheet.compute_vfr('30/1', '15/1')).to be(true)
  end

  it 'tolerates small mismatches within the 95% threshold' do
    expect(ContactSheet.compute_vfr('30000/1001', '30/1')).to be(false)
  end

  it 'returns false for malformed or missing rates' do
    expect(ContactSheet.compute_vfr('0/0', '30/1')).to be(false)
    expect(ContactSheet.compute_vfr('', '')).to be(false)
  end
end
